//
//  TypeSafeChannelHandler.swift
//  NIOEchoServer
//
//  Created by Johannes Weiß on 30/06/2017.
//

public protocol TypedChannelHandlerContext: class {
    associatedtype InboundOut
    associatedtype InboundUserEventOut
    associatedtype OutboundOut
    associatedtype OutboundUserEventOut

    var channel: Channel?  { get }

    var handler: ChannelHandler { get }
    var name: String  { get }
    var eventLoop: EventLoop  { get }

    func fireChannelRegistered()

    func fireChannelUnregistered()

    func fireChannelActive()

    func fireChannelInactive()

    func fireChannelRead(_ data: InboundOut)

    func fireChannelReadComplete()

    func fireChannelWritabilityChanged()

    func fireErrorCaught(_ error: Error)

    func fireUserInboundEventTriggered(_ event: InboundUserEventOut)

    func register(promise: EventLoopPromise<Void>?)

    func bind(to address: SocketAddress, promise: EventLoopPromise<Void>?)

    func connect(to address: SocketAddress, promise: EventLoopPromise<Void>?)
    func write(_ data: OutboundOut, promise: EventLoopPromise<Void>?)

    func flush()

    func writeAndFlush(_ data: OutboundOut, promise: EventLoopPromise<Void>?)

    func read()

    func close(promise: EventLoopPromise<Void>?)

    func triggerUserOutboundEvent(_ event: OutboundUserEventOut, promise: EventLoopPromise<Void>?)
}

public class TCHC<I, O, UI, UO>: TypedChannelHandlerContext {
    public typealias InboundOut = I
    public typealias OutboundOut = O
    public typealias InboundUserEventOut = UI
    public typealias OutboundUserEventOut = UO

    private let untypedCtx: ChannelHandlerContext
    private let forwardUntyped: Bool

    public init(_ untypedCtx: ChannelHandlerContext) {
        self.untypedCtx = untypedCtx
        self.forwardUntyped = true
    }

    /*
    public init(fireChannelRegistered: () -> Void,
                fireChannelUnregistered: () -> Void,
                fireChannelActive: () -> Void,
                fireChannelInactive: () -> Void,
                fireChannelRead: (I) -> Void,
                fireChannelReadComplete: () -> Void,
                fireChannelWritabilityChanged: () -> Void,
                fireErrorCaught: (Error) -> Void,
                fireUserInboundEventTriggered: (UI) -> Void
                ) {
        self.forwardUntyped = false
    }
 */

    public var channel: Channel? {
        return self.untypedCtx.channel
    }

    public var handler: ChannelHandler {
        return self.untypedCtx.handler
    }

    public var name: String {
        return self.untypedCtx.name
    }

    public var eventLoop: EventLoop {
        return self.untypedCtx.eventLoop
    }

    public func fireChannelRegistered() {
        return self.untypedCtx.fireChannelRegistered()
    }

    public func fireChannelUnregistered() {
        return self.untypedCtx.fireChannelRegistered()
    }

    public func fireChannelActive() {
        return self.untypedCtx.fireChannelActive()
    }

    public func fireChannelInactive() {
        return self.untypedCtx.fireChannelInactive()
    }

    public func fireChannelRead(_ data: I) {
        return self.untypedCtx.fireChannelRead(NIOAny(data))
    }

    public func fireChannelReadComplete() {
        return self.untypedCtx.fireChannelReadComplete()
    }

    public func fireChannelWritabilityChanged() {
        return self.untypedCtx.fireChannelWritabilityChanged()
    }

    public func fireErrorCaught(_ error: Error) {
        return self.untypedCtx.fireErrorCaught(error)
    }

    public func fireUserInboundEventTriggered(_ event: UI) {
        return self.untypedCtx.fireUserInboundEventTriggered(event)
    }

    public func register(promise: EventLoopPromise<Void>?) {
        return self.untypedCtx.register(promise: promise)
    }

    public func bind(to address: SocketAddress, promise: EventLoopPromise<Void>?) {
        return self.untypedCtx.bind(to: address, promise: promise)
    }

    public func connect(to address: SocketAddress, promise: EventLoopPromise<Void>?) {
        return self.untypedCtx.connect(to: address, promise: promise)
    }

    public func write(_ data: O, promise: EventLoopPromise<Void>?) {
        return self.untypedCtx.write(NIOAny(data), promise: promise)
    }

    public func flush() {
        return self.untypedCtx.flush()
    }

    public func writeAndFlush(_ data: O, promise: EventLoopPromise<Void>?) {
        return self.untypedCtx.writeAndFlush(NIOAny(data), promise: promise)
    }

    public func read() {
        return self.untypedCtx.read()
    }

    public func close(promise: EventLoopPromise<Void>?) {
        return self.untypedCtx.close(promise: promise)
    }

    public func triggerUserOutboundEvent(_ event: UO, promise: EventLoopPromise<Void>?) {
        return self.untypedCtx.triggerUserOutboundEvent(event, promise: promise)
    }
}

public protocol TypedChannelHandler : class {
    func handlerAdded(ctx: ChannelHandlerContext) throws
    func handlerRemoved(ctx: ChannelHandlerContext) throws
}

public protocol TypedChannelOutboundHandler : TypedChannelHandler {
    associatedtype OutboundIn
    associatedtype OutboundUserEventIn = Never

    associatedtype OutboundOut
    associatedtype InboundOut = Never
    associatedtype OutboundUserEventOut = Never
    associatedtype InboundUserEventOut = Never

    // TODO: should be the `associatedtype` one, just in case anyone wants to repro the crash
    // associatedtype Context = TCHC<InboundOut, OutboundOut, InboundUserEventOut, OutboundUserEventOut>
    typealias Context = TCHC<InboundOut, OutboundOut, InboundUserEventOut, OutboundUserEventOut>

    func register(ctx: Context, promise: EventLoopPromise<Void>?)
    func bind(ctx: Context, to: SocketAddress, promise: EventLoopPromise<Void>?)
    func connect(ctx: Context, to: SocketAddress, promise: EventLoopPromise<Void>?)
    func write(ctx: Context, data: OutboundOut, promise: EventLoopPromise<Void>?)
    func flush(ctx: Context, promise: EventLoopPromise<Void>?)
    func read(ctx: Context, promise: EventLoopPromise<Void>?)
    func close(ctx: Context, promise: EventLoopPromise<Void>?)
    func triggerUserOutboundEvent(ctx: Context, event: OutboundUserEventOut, promise: EventLoopPromise<Void>?)
}

public protocol TypedChannelInboundHandler : TypedChannelHandler {
    associatedtype InboundIn
    associatedtype InboundUserEventIn = Never

    associatedtype OutboundOut = Never
    associatedtype InboundOut = Never
    associatedtype OutboundUserEventOut = Never
    associatedtype InboundUserEventOut = Never

    // TODO: should be the `associatedtype` one, just in case anyone wants to repro the crash
    // associatedtype Context = TCHC<InboundOut, OutboundOut, InboundUserEventOut, OutboundUserEventOut>
    typealias Context = TCHC<InboundOut, OutboundOut, InboundUserEventOut, OutboundUserEventOut>

    func channelRegistered(ctx: Context)
    func channelUnregistered(ctx: Context)
    func channelActive(ctx: Context)
    func channelInactive(ctx: Context)
    func channelRead(ctx: Context, data: InboundIn)
    func channelReadComplete(ctx: Context)
    func channelWritabilityChanged(ctx: Context)
    func userInboundEventTriggered(ctx: Context, event: InboundUserEventIn)
    func errorCaught(ctx: Context, error: Error)
}

//  Default implementation for the ChannelHandler protocol
public extension TypedChannelHandler {

    public func handlerAdded(ctx: ChannelHandlerContext) {
        // Do nothing by default
    }

    public func handlerRemoved(ctx: ChannelHandlerContext) {
        // Do nothing by default
    }
}

public extension TypedChannelOutboundHandler {


    public func register(ctx: Context, promise: EventLoopPromise<Void>?) {
        ctx.register(promise: promise)
    }

    public func bind(ctx: Context, to address: SocketAddress, promise: EventLoopPromise<Void>?) {
        ctx.bind(to: address, promise: promise)
    }

    public func connect(ctx: Context, to address: SocketAddress, promise: EventLoopPromise<Void>?) {
        ctx.connect(to: address, promise: promise)
    }

    public func flush(ctx: Context, promise: EventLoopPromise<Void>?) {
        ctx.flush()
    }

    public func read(ctx: Context, promise: EventLoopPromise<Void>?) {
        ctx.read()
    }

    public func close(ctx: Context, promise: EventLoopPromise<Void>?) {
        ctx.close(promise: promise)
    }
}

public extension TypedChannelOutboundHandler where Self.OutboundIn == Self.OutboundOut {

    public func write(ctx: Context, data: OutboundIn, promise: EventLoopPromise<Void>?) {
        ctx.write(data, promise: promise)
    }
}

public extension TypedChannelOutboundHandler where Self.OutboundUserEventIn == Self.OutboundUserEventOut {

    public func triggerUserOutboundEvent(ctx: Context, event: OutboundUserEventOut, promise: EventLoopPromise<Void>?) {
        ctx.triggerUserOutboundEvent(event, promise: promise)
    }
}

public extension TypedChannelInboundHandler {

    public func channelRegistered(ctx: Context) {
        ctx.fireChannelRegistered()
    }

    public func channelUnregistered(ctx: Context) {
        ctx.fireChannelUnregistered()
    }

    public func channelActive(ctx: Context) {
        ctx.fireChannelActive()
    }

    public func channelInactive(ctx: Context) {
        ctx.fireChannelInactive()
    }


    public func channelReadComplete(ctx: Context) {
        ctx.fireChannelReadComplete()
    }

    public func channelWritabilityChanged(ctx: Context) {
        ctx.fireChannelWritabilityChanged()
    }


    public func errorCaught(ctx: Context, error: Error) {
        ctx.fireErrorCaught(error)
    }
}

/*
public extension TypedChannelInboundHandler where Self.InboundIn == Self.InboundOut {
    public func channelRead(ctx: Context, data: InboundIn) {
        ctx.fireChannelRead(data: data)
    }
}
 */

public extension TypedChannelInboundHandler where Self.InboundUserEventIn == Self.InboundUserEventOut {
    public func userInboundEventTriggered(ctx: Context, event: InboundUserEventIn) {
        ctx.fireUserInboundEventTriggered(event)
    }
}

public class _Box<T> {
    public var value: T!
    public init() {}
}

public class ForwardingChannelInboundHandler<I, U, IO, OO, IUO, OUO>: TypedChannelInboundHandler {
    public typealias InboundIn = I
    public typealias InboundUserEventIn = U

    public typealias InboundOut = IO
    public typealias OutboundOut = OO
    public typealias InboundUserEventOut = IUO
    public typealias OutboundUserEventOut = OUO

    //public typealias Context = TCHC<IO, OO, IUO, OUO>
    public init() {
        fatalError()
    }
    public init(
        channelRegistered: @escaping (Context) -> Void,
        channelUnregistered: @escaping (Context) -> Void,
        channelActive: @escaping (Context) -> Void,
        channelInactive: @escaping (Context) -> Void,
        channelRead: @escaping (Context, I) -> Void,
        channelReadComplete: @escaping (Context) -> Void,
        channelWritabilityChanged: @escaping (Context) -> Void,
        userInboundEventTriggered: @escaping (Context, U) -> Void,
        errorCaught: @escaping (Context, Error) -> Void
        ) {
        self.wrapped_channelRegistered = channelRegistered
        self.wrapped_channelUnregistered = channelUnregistered
        self.wrapped_channelActive = channelActive
        self.wrapped_channelInactive = channelInactive
        self.wrapped_channelRead = channelRead
        self.wrapped_channelReadComplete = channelReadComplete
        self.wrapped_channelWritabilityChanged = channelWritabilityChanged
        self.wrapped_userInboundEventTriggered = userInboundEventTriggered
        self.wrapped_errorCaught = errorCaught
    }

    private let wrapped_channelRegistered: (Context) -> Void
    public func channelRegistered(ctx: Context) {
        self.wrapped_channelRegistered(ctx)
    }

    private let wrapped_channelUnregistered: (Context) -> Void
    public func channelUnregistered(ctx: Context) {
        self.wrapped_channelUnregistered(ctx)
    }

    private let wrapped_channelActive: (Context) -> Void
    public func channelActive(ctx: Context) {
        self.wrapped_channelActive(ctx)
    }

    private let wrapped_channelInactive: (Context) -> Void
    public func channelInactive(ctx: Context) {
        self.wrapped_channelInactive(ctx)
    }

    private let wrapped_channelRead: (Context, I) -> Void
    public func channelRead(ctx: Context, data: I)  {
        self.wrapped_channelRead(ctx, data)
    }

    private let wrapped_channelReadComplete: (Context) -> Void
    public func channelReadComplete(ctx: Context) {
        self.wrapped_channelReadComplete(ctx)
    }

    private let wrapped_channelWritabilityChanged: (Context) -> Void
    public func channelWritabilityChanged(ctx: Context) {
        self.wrapped_channelWritabilityChanged(ctx)
    }

    private let wrapped_userInboundEventTriggered: (Context, U) -> Void
    public func userInboundEventTriggered(ctx: Context, event: U) {
        self.wrapped_userInboundEventTriggered(ctx, event)
    }

    private let wrapped_errorCaught: (Context, Error) -> Void
    public func errorCaught(ctx: Context, error: Error) {
        self.wrapped_errorCaught(ctx, error)
    }
}


public class TypeStrippedChannelInboundHandler<I, U, IO, OO, IUO, OUO>: ChannelInboundHandler, _ChannelInboundHandler {
    public typealias InboundIn = I
    public typealias InboundUserEventIn = U

    public typealias InboundOut = IO
    public typealias OutboundOut = OO
    public typealias InboundUserEventOut = IUO
    public typealias OutboundUserEventOut = OUO

    public init(
        channelRegistered: @escaping (ChannelHandlerContext) -> Void,
        channelUnregistered: @escaping (ChannelHandlerContext) -> Void,
        channelActive: @escaping (ChannelHandlerContext) -> Void,
        channelInactive: @escaping (ChannelHandlerContext) -> Void,
        channelRead: @escaping (ChannelHandlerContext, NIOAny) -> Void,
        channelReadComplete: @escaping (ChannelHandlerContext) -> Void,
        channelWritabilityChanged: @escaping (ChannelHandlerContext) -> Void,
        userInboundEventTriggered: @escaping (ChannelHandlerContext, Any) -> Void,
        errorCaught: @escaping (ChannelHandlerContext, Error) -> Void
        ) {
        self.wrapped_channelRegistered = channelRegistered
        self.wrapped_channelUnregistered = channelUnregistered
        self.wrapped_channelActive = channelActive
        self.wrapped_channelInactive = channelInactive
        self.wrapped_channelRead = channelRead
        self.wrapped_channelReadComplete = channelReadComplete
        self.wrapped_channelWritabilityChanged = channelWritabilityChanged
        self.wrapped_userInboundEventTriggered = userInboundEventTriggered
        self.wrapped_errorCaught = errorCaught
    }

    private let typedCtx: _Box<TCHC<IO, OO, IUO, OUO>> = _Box()

    public init<T: TypedChannelInboundHandler>(_ wrapped: T) where T.Context == TCHC<IO, OO, IUO, OUO>, T.InboundIn == I, T.InboundUserEventIn == U {
        let ctxBox = _Box<TCHC<IO, OO, IUO, OUO>>()
        self.wrapped_channelRegistered = { ctx in
            ctxBox.value = TCHC(ctx)
            wrapped.channelRegistered(ctx: ctxBox.value)
        }
        self.wrapped_channelUnregistered = { _ in
            ctxBox.value = nil
            wrapped.channelUnregistered(ctx: ctxBox.value)
        }
        self.wrapped_channelActive = { _ in
            wrapped.channelActive(ctx: ctxBox.value)
        }
        self.wrapped_channelInactive = { _ in
            wrapped.channelInactive(ctx: ctxBox.value)
        }
        self.wrapped_channelRead = { _, data in
            wrapped.channelRead(ctx: ctxBox.value, data: data.forceAs(type: T.InboundIn.self))
        }
        self.wrapped_channelReadComplete = { _ in
            wrapped.channelReadComplete(ctx: ctxBox.value)
        }
        self.wrapped_channelWritabilityChanged = { _ in
            wrapped.channelWritabilityChanged(ctx: ctxBox.value)
        }
        self.wrapped_userInboundEventTriggered = { ctx, event in
            wrapped.userInboundEventTriggered(ctx: ctxBox.value, event: event as! U)
        }
        self.wrapped_errorCaught = { _, error in
            wrapped.errorCaught(ctx: ctxBox.value, error: error)
        }
    }

    private let wrapped_channelRegistered: (ChannelHandlerContext) -> Void
    public func channelRegistered(ctx: ChannelHandlerContext) {
        self.wrapped_channelRegistered(ctx)
    }

    private let wrapped_channelUnregistered: (ChannelHandlerContext) -> Void
    public func channelUnregistered(ctx: ChannelHandlerContext) {
        self.wrapped_channelUnregistered(ctx)
    }

    private let wrapped_channelActive: (ChannelHandlerContext) -> Void
    public func channelActive(ctx: ChannelHandlerContext) {
        self.wrapped_channelActive(ctx)
    }

    private let wrapped_channelInactive: (ChannelHandlerContext) -> Void
    public func channelInactive(ctx: ChannelHandlerContext) {
        self.wrapped_channelInactive(ctx)
    }

    private let wrapped_channelRead: (ChannelHandlerContext, NIOAny) -> Void
    public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
        self.wrapped_channelRead(ctx, data)
    }

    private let wrapped_channelReadComplete: (ChannelHandlerContext) -> Void
    public func channelReadComplete(ctx: ChannelHandlerContext) {
        self.wrapped_channelReadComplete(ctx)
    }

    private let wrapped_channelWritabilityChanged: (ChannelHandlerContext) -> Void
    public func channelWritabilityChanged(ctx: ChannelHandlerContext) {
        self.wrapped_channelWritabilityChanged(ctx)
    }

    private let wrapped_userInboundEventTriggered: (ChannelHandlerContext, Any) -> Void
    public func userInboundEventTriggered(ctx: ChannelHandlerContext, event: Any) {
        self.wrapped_userInboundEventTriggered(ctx, event)
    }

    private let wrapped_errorCaught: (ChannelHandlerContext, Error) -> Void
    public func errorCaught(ctx: ChannelHandlerContext, error: Error) {
        self.wrapped_errorCaught(ctx, error)
    }
}

public func undefined<T>() -> T {
    fatalError()
}

public func makeUntyped<TX: TypedChannelInboundHandler>(_ handler: TX) -> _ChannelInboundHandler where TX.Context == TCHC<TX.InboundOut, TX.OutboundOut, TX.InboundUserEventOut, TX.OutboundUserEventOut> {
    return TypeStrippedChannelInboundHandler<TX.InboundIn, TX.InboundUserEventIn, TX.InboundOut, TX.OutboundOut, TX.InboundUserEventOut, TX.OutboundUserEventOut>(handler)
}

public func fuse<A: TypedChannelInboundHandler, B: TypedChannelInboundHandler>(_ left: A, _ right: B) ->
    ForwardingChannelInboundHandler<A.InboundIn, A.InboundUserEventIn, B.InboundOut, B.OutboundOut, B.InboundUserEventOut, B.OutboundUserEventOut> where
    A.InboundOut == B.InboundIn,
    A.InboundUserEventOut == B.InboundUserEventIn,
    A.OutboundOut == B.OutboundOut,
    A.Context == TCHC<A.InboundOut, A.OutboundOut, A.InboundUserEventOut, A.OutboundUserEventOut>,
    B.Context == TCHC<B.InboundOut, B.OutboundOut, B.InboundUserEventOut, B.OutboundUserEventOut> {

    let ctxA = TCHC<A.InboundOut, A.OutboundOut, A.InboundUserEventOut, A.OutboundUserEventOut>(undefined())
    return ForwardingChannelInboundHandler<A.InboundIn, A.InboundUserEventIn, B.InboundOut, B.OutboundOut, B.InboundUserEventOut, B.OutboundUserEventOut>(
        channelRegistered: { (ctx) in
    },
        channelUnregistered: { (ctx) in
    },
        channelActive: { (ctx) in
    },
        channelInactive: { (ctx) in
    },
        channelRead: { (ctx, data) in
            left.channelRead(ctx: ctxA, data: data)
            left.channelRead(ctx: ctxA, data: data)
    },
        channelReadComplete: { (ctx) in
    },
        channelWritabilityChanged: { (ctx) in
    },
        userInboundEventTriggered: { (ctx, event) in
    },
        errorCaught: { (ctx, err) in
    })
}

public class TestA: TypedChannelInboundHandler {
    public func channelRead(ctx: TCHC<UInt8, Int32, UInt16, UInt32>, data: Int8) {
        ctx.fireChannelRead(UInt8(data))
    }

    public func userInboundEventTriggered(ctx: TCHC<UInt8, Int32, UInt16, UInt32>, event: Int16) {
        ctx.fireUserInboundEventTriggered(UInt16(event))
    }


    public typealias InboundIn = Int8
    public typealias InboundUserEventIn = Int16

    public typealias OutboundOut = Int32
    public typealias InboundOut = UInt8
    public typealias OutboundUserEventOut = UInt32
    public typealias InboundUserEventOut = UInt16

    //public typealias Context = TCHC<UInt8, Int32, UInt16, UInt32>
}

public class TestB: TypedChannelInboundHandler {
    public func channelRead(ctx: TCHC<Float, Int32, Double, UInt32>, data: UInt8) {
        ctx.fireChannelRead(Float(data))
    }

    public func userInboundEventTriggered(ctx: TCHC<Float, Int32, Double, UInt32>, event: UInt16) {
        ctx.fireUserInboundEventTriggered(Double(event))
    }

    public typealias InboundIn = UInt8
    public typealias InboundUserEventIn = UInt16

    public typealias OutboundOut = Int32
    public typealias InboundOut = Float
    public typealias OutboundUserEventOut = UInt32
    public typealias InboundUserEventOut = Double

    //public typealias Context = TCHC<Float, Int32, Double, UInt32>
}

func whatevs() {
    let a = TestA()
    let b = TestB()
    let c = fuse(a, b)
    _ = c
}
