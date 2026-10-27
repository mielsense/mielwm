import AppKit

/// Three fingers sliding sideways on the trackpad: one workspace step per
/// swipe, decided once the fingers have travelled far enough. Points are
/// the touches' normalized positions (0...1 across the trackpad). Pure, so
/// tests feed it touches.
struct SwipeRecognizer {
    /// Share of the trackpad width the fingers travel before a swipe counts.
    static let threshold = 0.1
    private var start: CGPoint?
    private var done = false

    /// true: the next workspace (fingers moving left, as Spaces does), false: the previous one.
    mutating func feed(_ touches: [CGPoint]) -> Bool? {
        guard touches.count == 3 else { // lifted, or a fourth finger: start over
            start = nil
            done = false
            return nil
        }
        let mean = CGPoint(x: touches.map(\.x).reduce(0, +) / 3, y: touches.map(\.y).reduce(0, +) / 3)
        guard let s = start else { start = mean; return nil }
        guard !done else { return nil }
        let dx = mean.x - s.x, dy = mean.y - s.y
        guard abs(dx) > Self.threshold, abs(dx) > 1.5 * abs(dy) else { return nil }
        done = true
        return dx < 0
    }
}

/// Three-finger swipes on the trackpad, from an active tap at the HID level
/// on the main run loop, as SwipeAeroSpace does it: AppKit fills in an
/// event's touches only there. Every event goes on unchanged and the
/// callback does almost nothing, so a touch is held up for microseconds.
public final class SwipeMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var recognizer = SwipeRecognizer()
    private let handler: (_ forward: Bool) -> Void

    public init(handler: @escaping (_ forward: Bool) -> Void) {
        self.handler = handler
    }

    public var isOn: Bool { tap != nil }

    public func start() {
        guard tap == nil else { return }
        guard let port = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: NSEvent.EventTypeMask.gesture.rawValue, callback: swipeTapCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return log("three-finger swipes are off: no trackpad event tap (Accessibility?)") }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.tap = port
        self.source = source
    }

    public func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        self.source = nil
    }

    deinit { stop() }

    /// Main thread.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            recognizer = SwipeRecognizer()
            return
        }
        guard type.rawValue == NSEvent.EventType.gesture.rawValue, let ns = NSEvent(cgEvent: event) else { return }
        let touches = ns.allTouches()
        guard !touches.isEmpty else { return } // about half the frames of a gesture are empty: they mean nothing
        // A thumb or palm resting on the pad is not a finger; nor is one just lifted.
        let fingers = touches.filter { !$0.isResting && $0.phase != .ended && $0.phase != .cancelled }
        if let forward = recognizer.feed(fingers.map(\.normalizedPosition)) { handler(forward) }
    }
}

private let swipeTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    if let userInfo { Unmanaged<SwipeMonitor>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event) }
    return Unmanaged.passUnretained(event)
}
