//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
//  Contains ChannelHandler implementations which are generic and can be re-used easily.
//
//

import struct Dispatch.DispatchTime


/// A `ChannelHandler` that implements a backoff for a `ServerChannel` when accept produces an `IOError`.
/// These errors are often recoverable by reducing the rate at which we call accept.
public final class AcceptBackoffHandler: ChannelDuplexHandler {
    public typealias InboundIn = Channel
    public typealias OutboundIn = Channel

    private var nextReadDeadlineNS: TimeAmount.Value?
    private let backoffProvider: (IOError) -> TimeAmount?
    private var scheduledRead: Scheduled<Void>?

    /// Default implementation used as `backoffProvider` which delays accept by 1 second.
    public static func defaultBackoffProvider(error: IOError) -> TimeAmount? {
        return .seconds(1)
    }

    /// Create a new instance
    ///
    /// - parameters:
    ///     - backoffProvider: returns a `TimeAmount` which will be the amount of time to wait before attempting another `read`.
    public init(backoffProvider: @escaping (IOError) -> TimeAmount? = AcceptBackoffHandler.defaultBackoffProvider) {
        self.backoffProvider = backoffProvider
    }

    public func read(context: ChannelHandlerContext) {
        // If we already have a read scheduled there is no need to schedule another one.
        guard scheduledRead == nil else { return }

        if let deadline = self.nextReadDeadlineNS {
            let now = TimeAmount.Value(DispatchTime.now().uptimeNanoseconds)
            if now >= deadline {
                // The backoff already expired, just do a read.
                doRead(context)
            } else {
                // Schedule the read to be executed after the backoff time elapsed.
                scheduleRead(in: .nanoseconds(deadline - now), context: context)
            }
        } else {
            context.read()
        }
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        if let ioError = error as? IOError {
            if let amount = backoffProvider(ioError) {
                self.nextReadDeadlineNS = TimeAmount.Value(DispatchTime.now().uptimeNanoseconds) + amount.nanoseconds
                if let scheduled = self.scheduledRead {
                    scheduled.cancel()
                    scheduleRead(in: amount, context: context)
                }
            }
        }
        context.fireErrorCaught(error)
    }

    public func channelInactive(context: ChannelHandlerContext) {
        if let scheduled = self.scheduledRead {
            scheduled.cancel()
            self.scheduledRead = nil
        }
        self.nextReadDeadlineNS = nil
        context.fireChannelInactive()
    }

    public func handlerRemoved(context: ChannelHandlerContext) {
        if let scheduled = self.scheduledRead {
            // Cancel the previous scheduled read and trigger a read directly. This is needed as otherwise we may never read again.
            scheduled.cancel()
            self.scheduledRead = nil
            context.read()
        }
        self.nextReadDeadlineNS = nil
    }

    private func scheduleRead(in: TimeAmount, context: ChannelHandlerContext) {
        self.scheduledRead = context.eventLoop.scheduleTask(in: `in`) {
            self.doRead(context)
        }
    }

    private func doRead(_ context: ChannelHandlerContext) {
        /// Reset the backoff time and read.
        self.nextReadDeadlineNS = nil
        self.scheduledRead = nil
        context.read()
    }
}

/**
 ChannelHandler implementation which enforces back-pressure by stopping to read from the remote peer when it cannot write back fast enough.
 It will start reading again once pending data was written.
*/
public class BackPressureHandler: ChannelDuplexHandler {
    public typealias OutboundIn = NIOAny
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer
    public typealias OutboundOut = ByteBuffer

    private var pendingRead = false
    private var writable: Bool = true

    public init() { }

    public func read(context: ChannelHandlerContext) {
        if writable {
            context.read()
        } else {
            pendingRead = true
        }
    }

    public func channelWritabilityChanged(context: ChannelHandlerContext) {
        self.writable = context.channel.isWritable
        if writable {
            mayRead(context: context)
        } else {
            context.flush()
        }

        // Propagate the event as the user may still want to do something based on it.
        context.fireChannelWritabilityChanged()
    }

    public func handlerRemoved(context: ChannelHandlerContext) {
        mayRead(context: context)
    }

    private func mayRead(context: ChannelHandlerContext) {
        if pendingRead {
            pendingRead = false
            context.read()
        }
    }
}

/// Triggers an IdleStateEvent when a Channel has not performed read, write, or both operation for a while.
public class IdleStateHandler: ChannelDuplexHandler {
    public typealias InboundIn = NIOAny
    public typealias InboundOut = NIOAny
    public typealias OutboundIn = NIOAny
    public typealias OutboundOut = NIOAny

    ///A user event triggered by IdleStateHandler when a Channel is idle.
    public enum IdleStateEvent {
        /// Will be triggered when no write was performed for the specified amount of time
        case write
        /// Will be triggered when no read was performed for the specified amount of time
        case read
        /// Will be triggered when neither read nor write was performed for the specified amount of time
        case all
    }

    public let readTimeout: TimeAmount?
    public let writeTimeout: TimeAmount?
    public let allTimeout: TimeAmount?

    private var reading = false
    private var lastReadTime: DispatchTime = DispatchTime(uptimeNanoseconds: 0)
    private var lastWriteCompleteTime: DispatchTime = DispatchTime(uptimeNanoseconds: 0)
    private var scheduledReaderTask: Scheduled<Void>?
    private var scheduledWriterTask: Scheduled<Void>?
    private var scheduledAllTask: Scheduled<Void>?

    public init(readTimeout: TimeAmount? = nil, writeTimeout: TimeAmount? = nil, allTimeout: TimeAmount? = nil) {
        self.readTimeout = readTimeout
        self.writeTimeout = writeTimeout
        self.allTimeout = allTimeout
    }

    public func handlerAdded(context: ChannelHandlerContext) {
        if context.channel.isActive {
            initIdleTasks(context)
        }
    }

    public func handlerRemoved(context: ChannelHandlerContext) {
        cancelIdleTasks(context)
    }

    public func channelActive(context: ChannelHandlerContext) {
        initIdleTasks(context)
        context.fireChannelActive()
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if readTimeout != nil || allTimeout != nil {
            reading = true
        }
        context.fireChannelRead(data)
    }

    public func channelReadComplete(context: ChannelHandlerContext) {
        if (readTimeout != nil  || allTimeout != nil) && reading {
            lastReadTime = DispatchTime.now()
            reading = false
        }
        context.fireChannelReadComplete()
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        if writeTimeout == nil && allTimeout == nil {
            context.write(data, promise: promise)
            return
        }

        let writePromise = promise ?? context.eventLoop.newPromise()
        writePromise.futureResult.whenComplete {
            self.lastWriteCompleteTime = DispatchTime.now()
        }
        context.write(data, promise: writePromise)
    }

    private func shouldReschedule(_ context: ChannelHandlerContext) -> Bool {
        if context.channel.isActive {
            return true
        }
        return false
    }

    private func newReadTimeoutTask(_ context: ChannelHandlerContext, _ timeout: TimeAmount) -> (() -> Void) {
        return {
            guard self.shouldReschedule(context) else  {
                return
            }

            if self.reading {
                self.scheduledReaderTask = context.eventLoop.scheduleTask(in: timeout, self.newReadTimeoutTask(context, timeout))
                return
            }

            let diff = TimeAmount.Value(DispatchTime.now().uptimeNanoseconds) - TimeAmount.Value(self.lastReadTime.uptimeNanoseconds)
            if diff >= timeout.nanoseconds {
                // Reader is idle - set a new timeout and trigger an event through the pipeline
                self.scheduledReaderTask = context.eventLoop.scheduleTask(in: timeout, self.newReadTimeoutTask(context, timeout))

                context.fireUserInboundEventTriggered(IdleStateEvent.read)
            } else {
                // Read occurred before the timeout - set a new timeout with shorter delay.
                self.scheduledReaderTask = context.eventLoop.scheduleTask(in: .nanoseconds(timeout.nanoseconds - diff), self.newReadTimeoutTask(context, timeout))
            }
        }
    }

    private func newWriteTimeoutTask(_ context: ChannelHandlerContext, _ timeout: TimeAmount) -> (() -> Void) {
        return {
            guard self.shouldReschedule(context) else  {
                return
            }

            let lastWriteTime = self.lastWriteCompleteTime
            let diff = DispatchTime.now().uptimeNanoseconds - lastWriteTime.uptimeNanoseconds

            if diff >= timeout.nanoseconds {
                // Writer is idle - set a new timeout and notify the callback.
                self.scheduledWriterTask = context.eventLoop.scheduleTask(in: timeout, self.newWriteTimeoutTask(context, timeout))

                context.fireUserInboundEventTriggered(IdleStateEvent.write)
            } else {
                // Write occurred before the timeout - set a new timeout with shorter delay.
                self.scheduledWriterTask = context.eventLoop.scheduleTask(in: .nanoseconds(TimeAmount.Value(timeout.nanoseconds) - TimeAmount.Value(diff)), self.newWriteTimeoutTask(context, timeout))
            }
        }
    }

    private func newAllTimeoutTask(_ context: ChannelHandlerContext, _ timeout: TimeAmount) -> (() -> Void) {
        return {
            guard self.shouldReschedule(context) else  {
                return
            }

            if self.reading {
                self.scheduledReaderTask = context.eventLoop.scheduleTask(in: timeout, self.newAllTimeoutTask(context, timeout))
                return
            }
            let lastRead = self.lastReadTime
            let lastWrite = self.lastWriteCompleteTime

            let diff = TimeAmount.Value(DispatchTime.now().uptimeNanoseconds) - TimeAmount.Value((lastRead > lastWrite ? lastRead : lastWrite).uptimeNanoseconds)
            if diff >= timeout.nanoseconds {
                // Reader is idle - set a new timeout and trigger an event through the pipeline
                self.scheduledReaderTask = context.eventLoop.scheduleTask(in: timeout, self.newAllTimeoutTask(context, timeout))

                context.fireUserInboundEventTriggered(IdleStateEvent.all)
            } else {
                // Read occurred before the timeout - set a new timeout with shorter delay.
                self.scheduledReaderTask = context.eventLoop.scheduleTask(in: .nanoseconds(TimeAmount.Value(timeout.nanoseconds) - diff), self.newAllTimeoutTask(context, timeout))
            }
        }
    }

    private func schedule(_ context: ChannelHandlerContext, _ amount: TimeAmount?, _ body: @escaping (ChannelHandlerContext, TimeAmount) -> (() -> Void) ) -> Scheduled<Void>? {
        if let timeout = amount {
            return context.eventLoop.scheduleTask(in: timeout, body(context, timeout))
        }
        return nil
    }

    private func initIdleTasks(_ context: ChannelHandlerContext) {
        let now = DispatchTime.now()
        lastReadTime = now
        lastWriteCompleteTime = now
        scheduledReaderTask = schedule(context, readTimeout, newReadTimeoutTask)
        scheduledWriterTask = schedule(context, writeTimeout, newWriteTimeoutTask)
        scheduledAllTask = schedule(context, allTimeout, newAllTimeoutTask)
    }

    private func cancelIdleTasks(_ context: ChannelHandlerContext) {
        scheduledReaderTask?.cancel()
        scheduledWriterTask?.cancel()
        scheduledAllTask?.cancel()
        scheduledReaderTask = nil
        scheduledWriterTask = nil
        scheduledAllTask = nil
    }
}
