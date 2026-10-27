import AppKit
import MielCore
import os

/// Two CGEventTaps at the head of the session, on their own thread and run
/// loop: keys, modifiers and the middle button always; left and right
/// buttons, the wheel and gestures only while `TapRouter.wantsPointer`, so
/// every click, drag and scroll in other apps does not make a round trip
/// through this process. The callback only routes; handlers run later on
/// the main queue.
public final class EventTap {
    /// eventSourceUserData of events we post ourselves, so the tap lets them through.
    private static let replayMarker: Int64 = 0x4D49_454C // "MIEL"

    public var state: TapState {
        get { lockedState.withLock { $0 } }
        set {
            lockedState.withLock { $0 = newValue }
            thread?.perform { [weak self] in self?.syncPointer() } // the overview opening or closing
        }
    }

    private let lockedState = OSAllocatedUnfairLock(initialState: TapState())
    private let handler: (TapEvent) -> Void
    private var router = TapRouter() // tap thread only
    private var middleDown: CGEvent? // tap thread only, replayed if no pan follows
    private var tap: CFMachPort?
    private var pointerTap: CFMachPort?
    private var pointerOn = false // tap thread only
    private var listenOnly = false
    private var thread: RunLoopThread?

    public init(handler: @escaping (TapEvent) -> Void) {
        self.handler = handler
    }

    /// False without the Accessibility permission. `listenOnly` taps observe
    /// and never consume or post anything (tests).
    @discardableResult
    public func start(listenOnly: Bool = false) -> Bool {
        guard tap == nil else { return true }
        func mask(_ types: [CGEventType]) -> CGEventMask { types.reduce(CGEventMask(0)) { $0 | 1 << $1.rawValue } }
        func create(_ mask: CGEventMask) -> CFMachPort? {
            CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: listenOnly ? .listenOnly : .defaultTap,
                              eventsOfInterest: mask, callback: tapCallback, userInfo: Unmanaged.passUnretained(self).toOpaque())
        }
        guard let port = create(mask([.keyDown, .keyUp, .flagsChanged, .otherMouseDown, .otherMouseDragged, .otherMouseUp])),
              let pointer = create(mask([.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .rightMouseDragged,
                                         .rightMouseUp, .scrollWheel]) | NSEvent.EventTypeMask([.gesture, .magnify]).rawValue)
        else { return false }
        let thread = RunLoopThread(name: "mielwm.event-tap")
        self.listenOnly = listenOnly
        self.tap = port
        self.pointerTap = pointer
        self.thread = thread
        thread.startAndWait()
        // Events flow from here on; the pointer tap only once it is wanted.
        CGEvent.tapEnable(tap: pointer, enable: false)
        for p in [port, pointer] { CFRunLoopAddSource(thread.runLoop, CFMachPortCreateRunLoopSource(nil, p, 0), .commonModes) }
        CGEvent.tapEnable(tap: port, enable: true)
        thread.perform { [weak self] in self?.syncPointer() }
        return true
    }

    public func stop() {
        guard let tap, let pointerTap, let thread else { return }
        for p in [tap, pointerTap] {
            CGEvent.tapEnable(tap: p, enable: false)
            CFMachPortInvalidate(p)
        }
        thread.stop()
        self.tap = nil
        self.pointerTap = nil
        self.thread = nil
    }

    deinit { stop() }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            if pointerOn, let pointerTap { CGEvent.tapEnable(tap: pointerTap, enable: true) }
            dispatch(router.reset(held: Self.modifiers(CGEventSource.flagsState(.combinedSessionState))))
            syncPointer()
            return Unmanaged.passUnretained(event)
        }
        defer { syncPointer() }
        let state = self.state
        guard !listenOnly, event.getIntegerValueField(.eventSourceUserData) != Self.replayMarker,
              let input = Self.decode(type, event, wantsPinch: state.overviewOpen)
        else { return Unmanaged.passUnretained(event) }
        if case .mouse(.down, 2, _, _) = input { middleDown = event.copy() }
        let out = router.route(input, state)
        dispatch(out.events)
        if out.replayMiddleClick, let down = middleDown {
            // The originals, so modifiers and click count survive (⌘-middle-click).
            for replay in [down, event.copy()].compactMap({ $0 }) {
                replay.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
                replay.post(tap: .cghidEventTap)
            }
            middleDown = nil
        }
        return out.consume ? nil : Unmanaged.passUnretained(event)
    }

    /// Tap thread. Turns the pointer tap on or off to match the router.
    private func syncPointer() {
        guard let pointerTap else { return }
        let wanted = router.wantsPointer(state)
        guard wanted != pointerOn else { return }
        pointerOn = wanted
        CGEvent.tapEnable(tap: pointerTap, enable: wanted)
    }

    private func dispatch(_ events: [TapEvent]) {
        guard !events.isEmpty else { return }
        DispatchQueue.main.async { [handler] in events.forEach(handler) }
    }

    private static func decode(_ type: CGEventType, _ event: CGEvent, wantsPinch: Bool) -> TapInput? {
        let modifiers = modifiers(event.flags)
        let point = event.location
        switch type {
        case .keyDown, .keyUp:
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            if type == .keyDown { event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars) }
            return .key(down: type == .keyDown, KeyPress(
                keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)), modifiers: modifiers,
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                characters: String(utf16CodeUnits: chars, count: length)))
        case .flagsChanged:
            return .flags(modifiers)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged, .rightMouseDragged,
             .otherMouseDragged, .leftMouseUp, .rightMouseUp, .otherMouseUp:
            let phase: TapInput.Mouse = switch type {
            case .leftMouseDown, .rightMouseDown, .otherMouseDown: .down
            case .leftMouseUp, .rightMouseUp, .otherMouseUp: .up
            default: .dragged
            }
            return .mouse(phase, button: Int(event.getIntegerValueField(.mouseEventButtonNumber)), at: point, modifiers: modifiers)
        case .scrollWheel:
            return .scroll(lines: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), at: point, modifiers: modifiers)
        default:
            // Gesture events: only pinches matter, and only in the overview.
            guard wantsPinch, let ns = NSEvent(cgEvent: event), ns.type == .magnify else { return nil }
            return .magnify(Double(ns.magnification), at: point)
        }
    }

    public static func modifiers(_ flags: CGEventFlags) -> Modifiers {
        var m: Modifiers = []
        if flags.contains(.maskShift) { m.insert(.shift) }
        if flags.contains(.maskControl) { m.insert(.control) }
        if flags.contains(.maskAlternate) { m.insert(.option) }
        if flags.contains(.maskCommand) { m.insert(.command) }
        return m
    }
}

private let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
}
