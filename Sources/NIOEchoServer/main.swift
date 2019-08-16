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
import NIO

private final class CasingHandler: TypeSafeChannelHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    enum How {
        case lower
        case upper
        case cRaZy
        case random
        case asIs
    }

    enum Where {
        case `in`
        case out
        case duplex
    }

    private let how: How
    private let `where`: Where

    init(how: How, where: Where = .duplex) {
        self.how = how
        self.where = `where`
    }

    func changeCase(_ byte: UInt8, index: Int) -> UInt8 {
        switch self.how {
        case .lower:
            return .init(tolower(.init(byte)))
        case .upper:
            return .init(toupper(.init(byte)))
        case .cRaZy:
            return .init((index % 2 == 0 ? toupper : tolower)(.init(byte)))
        case .random:
            return .init((Bool.random() ? toupper : tolower)(.init(byte)))
        case .asIs:
            return byte
        }
    }

    func channelRead(context: Context, data: ByteBuffer) {
        var data = data
        switch self.where {
        case .in, .duplex:
            data.withUnsafeMutableReadableBytes { ptr in
                for i in ptr.indices {
                    ptr[i] = self.changeCase(ptr[i], index: i)
                }
            }
        case .out:
            ()
        }
        context.fireChannelRead(data)
    }

    func write(context: Context, data: ByteBuffer, promise: EventLoopPromise<Void>?) {
        var data = data
        switch self.where {
        case .out, .duplex:
            data.withUnsafeMutableReadableBytes { ptr in
                for i in ptr.indices {
                    ptr[i] = self.changeCase(ptr[i], index: i)
                }
            }
        case .in:
            ()
        }
        context.write(data, promise: promise)
    }
}


private final class EchoHandler: TypeSafeChannelHandler {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = Never
    public typealias OutboundOut = ByteBuffer
    public typealias OutboundIn = Never

    public func channelRead(context: Context, data: ByteBuffer) {
        context.write(data, promise: nil)
    }

    // Flush it out. This can make use of gathering writes if multiple buffers are pending
    public func channelReadComplete(context: Context) {
        context.flush()
    }

    public func errorCaught(context: Context, error: Error) {
        print("error: ", error)

        // As we are not really interested getting notified on success or failure we just pass nil as promise to
        // reduce allocations.
        context.close(promise: nil)
    }
}
let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
let bootstrap = ServerBootstrap(group: group)
    // Specify backlog and enable SO_REUSEADDR for the server itself
    .serverChannelOption(ChannelOptions.backlog, value: 256)
    .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)

    // Set the handlers that are appled to the accepted Channels
    .childChannelInitializer { channel in
        // Ensure we don't read faster than we can write by adding the BackPressureHandler into the pipeline.
        channel.pipeline.addHandler(BackPressureHandler()).flatMap { v in
            return channel.pipeline.addHandler(CasingHandler(how: .asIs) <==> CasingHandler(how: .random) <==> EchoHandler())
        }
    }

    // Enable SO_REUSEADDR for the accepted Channels
    .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
    .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
    .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
defer {
    try! group.syncShutdownGracefully()
}

// First argument is the program path
let arguments = CommandLine.arguments
let arg1 = arguments.dropFirst().first
let arg2 = arguments.dropFirst(2).first

let defaultHost = "::1"
let defaultPort = 9999

enum BindTo {
    case ip(host: String, port: Int)
    case unixDomainSocket(path: String)
}

let bindTarget: BindTo
switch (arg1, arg1.flatMap(Int.init), arg2.flatMap(Int.init)) {
case (.some(let h), _ , .some(let p)):
    /* we got two arguments, let's interpret that as host and port */
    bindTarget = .ip(host: h, port: p)
case (.some(let portString), .none, _):
    /* couldn't parse as number, expecting unix domain socket path */
    bindTarget = .unixDomainSocket(path: portString)
case (_, .some(let p), _):
    /* only one argument --> port */
    bindTarget = .ip(host: defaultHost, port: p)
default:
    bindTarget = .ip(host: defaultHost, port: defaultPort)
}

let channel = try { () -> Channel in
    switch bindTarget {
    case .ip(let host, let port):
        return try bootstrap.bind(host: host, port: port).wait()
    case .unixDomainSocket(let path):
        return try bootstrap.bind(unixDomainSocketPath: path).wait()
    }
}()

print("Server started and listening on \(channel.localAddress!)")

// This will never unblock as we don't close the ServerChannel
try channel.closeFuture.wait()

print("Server closed")
