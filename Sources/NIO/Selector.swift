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

import Dispatch

private enum SelectorLifecycleState {
    case open
    case closing
    case closed
}

private extension timespec {
    init(timeAmount amount: TimeAmount) {
        let nsecPerSec: Int = 1_000_000_000
        let ns = amount.nanoseconds
        let sec = ns / nsecPerSec
        self = timespec(tv_sec: sec, tv_nsec: ns - sec * nsecPerSec)
    }
}

private extension Optional {
    func withUnsafeOptionalPointer<T>(_ body: (UnsafePointer<Wrapped>?) throws -> T) rethrows -> T {
        if var this = self {
            return try withUnsafePointer(to: &this) { x in
                try body(x)
            }
        } else {
            return try body(nil)
        }
    }
}

private struct KQueueEventFilterSet: OptionSet, Equatable {
    typealias RawValue = UInt8

    let rawValue: UInt8

    static let _none = KQueueEventFilterSet(rawValue: 0)
    static let except = KQueueEventFilterSet(rawValue: 1 << 1)
    static let read = KQueueEventFilterSet(rawValue: 1 << 2)
    static let write = KQueueEventFilterSet(rawValue: 1 << 3)

    init(rawValue: RawValue) {
        self.rawValue = rawValue
    }
}

private struct EPollFilterSet: OptionSet, Equatable {
    typealias RawValue = UInt8

    let rawValue: UInt8

    static let _none = EPollFilterSet(rawValue: 0)
    static let hangup = EPollFilterSet(rawValue: 1 << 0)
    static let readHangup = EPollFilterSet(rawValue: 1 << 1)
    static let input = EPollFilterSet(rawValue: 1 << 2)
    static let output = EPollFilterSet(rawValue: 1 << 3)
    static let error = EPollFilterSet(rawValue: 1 << 4)

    init(rawValue: RawValue) {
        self.rawValue = rawValue
    }
}

extension KQueueEventFilterSet {
    init(selectorEventSet: SelectorEventSet) {
        var thing: KQueueEventFilterSet = .init(rawValue: 0)
        if selectorEventSet.contains(.read) {
            thing.formUnion(.read)
        }
        if selectorEventSet.contains(.write) {
            thing.formUnion(.write)
        }
        if selectorEventSet.contains(.readEOF) && !thing.contains(.read) {
            thing.formUnion(.except)
        }
        self = thing
    }
}

extension EPollFilterSet {
    init(selectorEventSet: SelectorEventSet) {
        var thing: EPollFilterSet = [.error, .hangup]
        if selectorEventSet.contains(.read) {
            thing.formUnion(.input)
        }
        if selectorEventSet.contains(.write) {
            thing.formUnion(.output)
        }
        if selectorEventSet.contains(.readEOF) {
            thing.formUnion(.readHangup)
        }
        self = thing
    }
}


///  A `Selector` allows a user to register different `Selectable` sources to an underlying OS selector, and for that selector to notify them once IO is ready for them to process.
///
/// This implementation offers an consistent API over epoll (for linux) and kqueue (for Darwin, BSD).
/* this is deliberately not thread-safe, only the wakeup() function may be called unprotectedly */
final class Selector<R: Registration> {
    private var lifecycleState: SelectorLifecycleState

    #if os(Linux)
    private typealias EventType = Epoll.epoll_event
    private let eventfd: Int32
    private let timerfd: Int32
    private var earliestTimer: UInt64 = UInt64.max
    #else
    private typealias EventType = kevent
    #endif

    private let fd: Int32
    private var eventsCapacity = 64
    private var events: UnsafeMutablePointer<EventType>
    private var registrations = [Int: R]()

    private static func allocateEventsArray(capacity: Int) -> UnsafeMutablePointer<EventType> {
        let events: UnsafeMutablePointer<EventType> = UnsafeMutablePointer.allocate(capacity: capacity)
        events.initialize(to: EventType())
        return events
    }

    private static func deallocateEventsArray(events: UnsafeMutablePointer<EventType>, capacity: Int) {
        events.deinitialize(count: capacity)
        events.deallocate()
    }

    private func growEventArrayIfNeeded(ready: Int) {
        guard ready == eventsCapacity else {
            return
        }
        Selector.deallocateEventsArray(events: events, capacity: eventsCapacity)

        // double capacity
        eventsCapacity = ready << 1
        events = Selector.allocateEventsArray(capacity: eventsCapacity)
    }

    init() throws {
        events = Selector.allocateEventsArray(capacity: eventsCapacity)
        self.lifecycleState = .closed

#if os(Linux)
        fd = try Epoll.epoll_create(size: 128)
        eventfd = try EventFd.eventfd(initval: 0, flags: Int32(EventFd.EFD_CLOEXEC | EventFd.EFD_NONBLOCK))
        timerfd = try TimerFd.timerfd_create(clockId: CLOCK_MONOTONIC, flags: Int32(TimerFd.TFD_CLOEXEC | TimerFd.TFD_NONBLOCK))

        self.lifecycleState = .open

        var ev = Epoll.epoll_event()
        ev.events = Selector.toEpollEvents(interested: [.read])
        ev.data.fd = eventfd

        _ = try Epoll.epoll_ctl(epfd: self.fd, op: Epoll.EPOLL_CTL_ADD, fd: eventfd, event: &ev)

        var timerev = Epoll.epoll_event()
        timerev.events = Epoll.EPOLLIN.rawValue | Epoll.EPOLLERR.rawValue | Epoll.EPOLLRDHUP.rawValue | Epoll.EPOLLET.rawValue
        timerev.data.fd = timerfd
        _ = try Epoll.epoll_ctl(epfd: self.fd, op: Epoll.EPOLL_CTL_ADD, fd: timerfd, event: &timerev)
#else
        fd = try KQueue.kqueue()
        self.lifecycleState = .open

        var event = kevent()
        event.ident = 0
        event.filter = Int16(EVFILT_USER)
        event.fflags = UInt32(NOTE_FFNOP)
        event.data = 0
        event.udata = nil
        event.flags = UInt16(EV_ADD | EV_ENABLE | EV_CLEAR)

        try keventChangeSetOnly(event: &event, numEvents: 1)
#endif
    }

    deinit {
        assert(self.lifecycleState == .closed, "Selector \(self.lifecycleState) (expected .closed) on deinit")
        Selector.deallocateEventsArray(events: events, capacity: eventsCapacity)

        /* this is technically a bad idea as we're abusing ARC to deallocate scarce resources (a file descriptor)
         for us. However, this is used for the event loop so there shouldn't be much churn.
         The reason we do this is because `self.wakeup()` may (and will!) be called on arbitrary threads. To not
         suffer from race conditions we would need to protect waking the selector up and closing the selector. That
         is likely to cause performance problems. By abusing ARC, we get the guarantee that there won't be any future
         wakeup calls as there are no references to this selector left. 💁
         */
#if os(Linux)
        try! Posix.close(descriptor: self.eventfd)
#else
        try! Posix.close(descriptor: self.fd)
#endif
    }


#if os(Linux)
    private static func toEpollEvents(interested: SelectorEventSet) -> UInt32 {
        // Also merge EPOLLRDHUP in so we can easily detect connection-reset

        var filter: UInt32 = 0
        let epollFilters = EPollFilterSet(selectorEventSet: interested)
        if epollFilters.contains(.error) {
            filter |= Epoll.EPOLLERR.rawValue
        }
        if epollFilters.contains(.hangup) {
            filter |= Epoll.EPOLLHUP.rawValue
        }
        if epollFilters.contains(.input) {
            filter |= Epoll.EPOLLIN.rawValue
        }
        if epollFilters.contains(.output) {
            filter |= Epoll.EPOLLOUT.rawValue
        }
        if epollFilters.contains(.readHangup) {
            filter |= Epoll.EPOLLRDHUP.rawValue
        }
        assert(filter & Epoll.EPOLLHUP.rawValue != 0) // not maskable
        assert(filter & Epoll.EPOLLERR.rawValue != 0) // always interested
        return filter
    }
#else
    private func toKQueueTimeSpec(strategy: SelectorStrategy) -> timespec? {
        switch strategy {
        case .block:
            return nil
        case .now:
            return timespec(tv_sec: 0, tv_nsec: 0)
        case .blockUntilTimeout(let nanoseconds):
            return timespec(timeAmount: nanoseconds)
        }
    }

    private func keventChangeSetOnly(event: UnsafePointer<kevent>?, numEvents: Int32) throws {
        do {
            _ = try KQueue.kevent(kq: self.fd, changelist: event, nchanges: numEvents, eventlist: nil, nevents: 0, timeout: nil)
        } catch let err as IOError {
            if err.errnoCode == EINTR {
                // See https://www.freebsd.org/cgi/man.cgi?query=kqueue&sektion=2
                // When kevent() call fails with EINTR error, all changes in the changelist have been applied.
                return
            }
            throw err
        }
    }

    private func register_kqueue<S: Selectable>(selectable: S, interested: SelectorEventSet, oldInterested: SelectorEventSet?) throws {
        let oldKQueueFilters = oldInterested.map { KQueueEventFilterSet(selectorEventSet: $0) } ?? KQueueEventFilterSet._none
        let newKQueueFilters = KQueueEventFilterSet(selectorEventSet: interested)
        let differences = oldKQueueFilters.symmetricDifference(newKQueueFilters)
        assert(interested.contains(.reset))
        assert(oldInterested?.contains(.reset) ?? true)

        func apply(event: KQueueEventFilterSet) -> UInt16? {
            guard differences.contains(event) else {
                return nil
            }
            return UInt16(newKQueueFilters.contains(event) ? EV_ADD : EV_DELETE)
        }

        // Allocated on the stack
        var events = (kevent(), kevent(), kevent())
//        print("from \(oldInterested) to \(interested)")
//        print("from \(oldKQueueFilters.rawValue) \(newKQueueFilters.rawValue)")
        try selectable.withUnsafeFileDescriptor { fd in
            try withUnsafeMutableBytes(of: &events) { event_ptr in
                precondition(MemoryLayout<kevent>.size * 3 == event_ptr.count)
                let ptr = event_ptr.baseAddress!.bindMemory(to: kevent.self, capacity: 3)

                var index: Int = 0
                for (event, filter) in [(KQueueEventFilterSet.read, EVFILT_READ), (.write, EVFILT_WRITE), (.except, EVFILT_EXCEPT)] {
                    if let flags = apply(event: event) {
                        //print("fd \(fd), \(flags == EV_ADD ? "+" : "-")\(event.rawValue)")
                        ptr[index].ident = UInt(fd)
                        ptr[index].filter = Int16(filter)
                        ptr[index].flags = flags
                        index += 1
                    }
                }
                if index > 0 {
                    try keventChangeSetOnly(event: ptr, numEvents: Int32(index))
                }
            }
        }
    }
#endif

    /// Register `Selectable` on the `Selector`.
    ///
    /// - parameters:
    ///     - selectable: The `Selectable` to register.
    ///     - interested: The `SelectorEventSet` in which we are interested and want to be notified about.
    ///     - makeRegistration: Creates the registration data for the given `SelectorEventSet`.
    func register<S: Selectable>(selectable: S, interested: SelectorEventSet, makeRegistration: (SelectorEventSet) -> R) throws {
        assert(interested.contains(.reset))
        guard self.lifecycleState == .open else {
            throw IOError(errnoCode: EBADF, reason: "can't register on selector as it's \(self.lifecycleState).")
        }

        try selectable.withUnsafeFileDescriptor { fd in
            assert(registrations[Int(fd)] == nil)
            #if os(Linux)
                var ev = Epoll.epoll_event()
                ev.events = Selector.toEpollEvents(interested: interested)
                ev.data.fd = fd

                _ = try Epoll.epoll_ctl(epfd: self.fd, op: Epoll.EPOLL_CTL_ADD, fd: fd, event: &ev)
            #else
                try register_kqueue(selectable: selectable, interested: interested, oldInterested: nil)
            #endif
            registrations[Int(fd)] = makeRegistration(interested)
        }
    }

    /// Re-register `Selectable`, must be registered via `register` before.
    ///
    /// - parameters:
    ///     - selectable: The `Selectable` to re-register.
    ///     - interested: The `SelectorEventSet` in which we are interested and want to be notified about.
    func reregister<S: Selectable>(selectable: S, interested: SelectorEventSet) throws {
        guard self.lifecycleState == .open else {
            throw IOError(errnoCode: EBADF, reason: "can't re-register on selector as it's \(self.lifecycleState).")
        }
        try selectable.withUnsafeFileDescriptor { fd in
            var reg = registrations[Int(fd)]!

            #if os(Linux)
                var ev = Epoll.epoll_event()
                ev.events = Selector.toEpollEvents(interested: interested)
                ev.data.fd = fd

                _ = try Epoll.epoll_ctl(epfd: self.fd, op: Epoll.EPOLL_CTL_MOD, fd: fd, event: &ev)
            #else
                try register_kqueue(selectable: selectable, interested: interested, oldInterested: reg.interested)
            #endif
            reg.interested = interested
            registrations[Int(fd)] = reg
        }
    }

    /// Deregister `Selectable`, must be registered via `register` before.
    ///
    /// After the `Selectable is deregistered no `SelectorEventSet` will be produced anymore for the `Selectable`.
    ///
    /// - parameters:
    ///     - selectable: The `Selectable` to deregister.
    func deregister<S: Selectable>(selectable: S) throws {
        guard self.lifecycleState == .open else {
            throw IOError(errnoCode: EBADF, reason: "can't deregister from selector as it's \(self.lifecycleState).")
        }
        try selectable.withUnsafeFileDescriptor { fd in
            guard let reg = registrations.removeValue(forKey: Int(fd)) else {
                return
            }

            #if os(Linux)
                var ev = Epoll.epoll_event()
                _ = try Epoll.epoll_ctl(epfd: self.fd, op: Epoll.EPOLL_CTL_DEL, fd: fd, event: &ev)
            #else
                try register_kqueue(selectable: selectable, interested: .reset, oldInterested: reg.interested)
            #endif
        }
    }

    /// Apply the given `SelectorStrategy` and execute `fn` once it's complete (which may produce `SelectorEvent`s to handle).
    ///
    /// - parameters:
    ///     - strategy: The `SelectorStrategy` to apply
    ///     - body: The function to execute for each `SelectorEvent` that was produced.
    func whenReady(strategy: SelectorStrategy, _ body: (SelectorEvent<R>) throws -> Void) throws -> Void {
        guard self.lifecycleState == .open else {
            throw IOError(errnoCode: EBADF, reason: "can't call whenReady for selector as it's \(self.lifecycleState).")
        }

#if os(Linux)
        let ready: Int

        switch strategy {
        case .now:
            ready = Int(try Epoll.epoll_wait(epfd: self.fd, events: events, maxevents: Int32(eventsCapacity), timeout: 0))
        case .blockUntilTimeout(let timeAmount):
            // Only call timerfd_settime if we not already scheduled one that will cover it.
            // This guards against calling timerfd_settime if not needed as this is generally speaking
            // expensive.
            let next = DispatchTime.now().uptimeNanoseconds + UInt64(timeAmount.nanoseconds)
            if next < self.earliestTimer {
                self.earliestTimer = next

                var ts = itimerspec()
                ts.it_value = timespec(timeAmount: timeAmount)
                try TimerFd.timerfd_settime(fd: timerfd, flags: 0, newValue: &ts, oldValue: nil)
            }
            fallthrough
        case .block:
            ready = Int(try Epoll.epoll_wait(epfd: self.fd, events: events, maxevents: Int32(eventsCapacity), timeout: -1))
        }

        for i in 0..<ready {
            let ev = events[i]
            switch ev.data.fd {
            case eventfd:
                var val = EventFd.eventfd_t()
                // Consume event
                _ = try EventFd.eventfd_read(fd: eventfd, value: &val)
            case timerfd:
                // Consume event
                var val: UInt = 0
                // We are not interested in the result
                _ = Glibc.read(timerfd, &val, MemoryLayout<UInt>.size)

                // Processed the earliest set timer so reset it.
                self.earliestTimer = UInt64.max
            default:
                // If the registration is not in the Map anymore we deregistered it during the processing of whenReady(...). In this case just skip it.
                if let registration = registrations[Int(ev.data.fd)] {
                    var selectorEvent: SelectorEvent = ._none
                    if ev.events & Epoll.EPOLLIN.rawValue != 0 {
                        selectorEvent.formUnion(.read)
                    }
                    if ev.events & Epoll.EPOLLOUT.rawValue != 0 {
                        selectorEvent.formUnion(.write)
                    }
                    if ev.events & Epoll.EPOLLRDHUP.rawValue != 0 {
                        selectorEvent.formUnion(.readEOF)
                    }
                    if ev.events & Epoll.EPOLLHUP.rawValue != 0 || ev.events & Epoll.EPOLLERR.rawValue != 0 {
                        selectorEvent.formUnion(.reset)
                    }

                    assert(selectorEvent.isSubset(of: registration.interested))
                    try body((SelectorEvent(io: selectorEvent, registration: registration)))
                }
            }
        }
        growEventArrayIfNeeded(ready: ready)
#else
        let timespec = toKQueueTimeSpec(strategy: strategy)
        let ready = try timespec.withUnsafeOptionalPointer { ts in
            Int(try KQueue.kevent(kq: self.fd, changelist: nil, nchanges: 0, eventlist: events, nevents: Int32(eventsCapacity), timeout: ts))
        }

        for i in 0..<ready {
            let ev = events[i]
            var selectorEvent: SelectorEventSet = ._none
            switch Int32(ev.filter) {
            case EVFILT_USER:
                // woken-up by the user, just ignore
                continue
            case EVFILT_READ:
                selectorEvent.formUnion(.read)
                fallthrough
            case EVFILT_EXCEPT:
                if Int32(ev.flags) & EV_EOF != 0 {
                    print("EOF")
                    selectorEvent.formUnion(.readEOF)
                }
                if ev.fflags != 0 {
                    selectorEvent.formUnion(.reset)
                    print("RESET \(Int32(ev.filter) == EVFILT_READ ? "read": "except")")
                }
            case EVFILT_WRITE:
                selectorEvent.formUnion(.write)
            default:
                // We only use EVFILT_USER, EVFILT_READ and EVFILT_WRITE.
                fatalError("unexpected filter \(ev.filter)")
            }
            if selectorEvent != ._none {
                if let registration = registrations[Int(ev.ident)] {
                    if !registration.interested.contains(.readEOF) && selectorEvent.contains(.readEOF) {
                        selectorEvent.subtract(.readEOF)
                    }
                    assert(selectorEvent.isSubset(of: registration.interested))
                    try body((SelectorEvent(io: selectorEvent, registration: registration)))
                }
            }
        }

        growEventArrayIfNeeded(ready: ready)
#endif
    }

    /// Close the `Selector`.
    ///
    /// After closing the `Selector` it's no longer possible to use it.
    public func close() throws {
        guard self.lifecycleState == .open else {
            throw IOError(errnoCode: EBADF, reason: "can't close selector as it's \(self.lifecycleState).")
        }
        self.lifecycleState = .closed

        self.registrations.removeAll()

        /* note, we can't close `self.fd` (on macOS) or `self.eventfd` (on Linux) here as that's read unprotectedly and might lead to race conditions. Instead, we abuse ARC to close it for us. */
#if os(Linux)
        _ = try Posix.close(descriptor: self.timerfd)
#endif

#if os(Linux)
        /* `self.fd` is used as the event file descriptor to wake kevent() up so can't be closed here on macOS */
        _ = try Posix.close(descriptor: self.fd)
#endif
    }

    /* attention, this may (will!) be called from outside the event loop, ie. can't access mutable shared state (such as `self.open`) */
    func wakeup() throws {

#if os(Linux)
        /* this is fine as we're abusing ARC to close `self.eventfd` */
        _ = try EventFd.eventfd_write(fd: self.eventfd, value: 1)
#else
        var event = kevent()
        event.ident = 0
        event.filter = Int16(EVFILT_USER)
        event.fflags = UInt32(NOTE_TRIGGER | NOTE_FFNOP)
        event.data = 0
        event.udata = nil
        event.flags = 0
        try keventChangeSetOnly(event: &event, numEvents: 1)
#endif
    }
}

extension Selector: CustomStringConvertible {
    var description: String {
        return "Selector { descriptor = \(self.fd) }"
    }
}

/// An event that is triggered once the `Selector` was able to select something.
struct SelectorEvent<R> {
    public let registration: R
    public let io: SelectorEventSet

    /// Create new instance
    ///
    /// - parameters:
    ///     - io: The `SelectorEventSet` that triggered this event.
    ///     - registration: The registration that belongs to the event.
    init(io: SelectorEventSet, registration: R) {
        self.io = io
        self.registration = registration
    }

    /// Create new instance
    ///
    /// - parameters:
    ///     - readable: `true` if readable.
    ///     - writable: `true` if writable
    ///     - registration: The registration that belongs to the event.
    init(readable: Bool, writable: Bool, registration: R) {
        fatalError("bad bad constructor")
        var io: SelectorEventSet = .reset
        if readable {
            io.formUnion(.read)
        }
        if writable {
            io.formUnion(.write)
        }
        self.io = io
        self.registration = registration
    }
}

internal extension Selector where R == NIORegistration {
    /// Gently close the `Selector` after all registered `Channel`s are closed.
    internal func closeGently(eventLoop: EventLoop) -> EventLoopFuture<Void> {
        guard self.lifecycleState == .open else {
            return eventLoop.newFailedFuture(error: IOError(errnoCode: EBADF, reason: "can't close selector gently as it's \(self.lifecycleState)."))
        }

        let futures: [EventLoopFuture<Void>] = self.registrations.map { (_, reg: NIORegistration) -> EventLoopFuture<Void> in
            // The futures will only be notified (of success) once also the closeFuture of each Channel is notified.
            // This only happens after all other actions on the Channel is complete and all events are propagated through the
            // ChannelPipeline. We do this to minimize the risk to left over any tasks / promises that are tied to the
            // EventLoop itself.
            func closeChannel(_ chan: Channel) -> EventLoopFuture<Void> {
                chan.close(promise: nil)
                return chan.closeFuture
            }

            switch reg {
            case .serverSocketChannel(let chan, _):
                return closeChannel(chan)
            case .socketChannel(let chan, _):
                return closeChannel(chan)
            case .datagramChannel(let chan, _):
                return closeChannel(chan)
            }
        }.map { future in
            future.thenIfErrorThrowing { error in
                if let error = error as? ChannelError, error == .alreadyClosed {
                    return ()
                } else {
                    throw error
                }
            }
        }

        guard futures.count > 0 else {
            return eventLoop.newSucceededFuture(result: ())
        }

        return EventLoopFuture<Void>.andAll(futures, eventLoop: eventLoop)
    }
}

/// The strategy used for the `Selector`.
enum SelectorStrategy {
    /// Block until there is some IO ready to be processed or the `Selector` is explicitly woken up.
    case block

    /// Block until there is some IO ready to be processed, the `Selector` is explicitly woken up or the given `TimeAmount` elapsed.
    case blockUntilTimeout(TimeAmount)

    /// Try to select all ready IO at this point in time without blocking at all.
    case now
}

/// The IO for which we want to be notified.
@available(*, deprecated, message: "IOEvent was made public by accident, is no longer removed internally and will be removed with SwiftNIO 2.0.0")
public enum IOEvent {
    /// Something is ready to be read.
    case read

    /// Its possible to write some data again.
    case write

    /// Combination of `read` and `write`.
    case all

    /// Not interested in any event.
    case none
}

struct SelectorEventSet: OptionSet, Equatable {

    typealias RawValue = UInt8

    let rawValue: UInt8

    static let _none = SelectorEventSet(rawValue: 0)
    static let reset = SelectorEventSet(rawValue: 1 << 0)
    static let readEOF = SelectorEventSet(rawValue: 1 << 1)
    static let read = SelectorEventSet(rawValue: 1 << 2)
    static let write = SelectorEventSet(rawValue: 1 << 3)

    init(rawValue: SelectorEventSet.RawValue) {
        self.rawValue = rawValue
    }
}
