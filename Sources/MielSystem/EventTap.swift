import AppKit
import Carbon.HIToolbox
import os
import MielCore

// MARK: - Chords and the binding table

/// A physical key plus exact modifiers. Key codes are positions on an ANSI
/// keyboard, like AeroSpace's default qwerty mapping.
public struct Chord: Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(_ keyCode: UInt16, _ modifiers: Modifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Parses "ctrl+opt+g", "alt-shift-left", "cmd+,". Modifier names:
    /// ctrl/control, opt/option/alt, cmd/command/super, shift. nil if any
    /// part is unknown or there is no key.
    public init?(_ text: String) {
        var modifiers: Modifiers = []
        var key: UInt16?
        let parts = text.lowercased().split(omittingEmptySubsequences: false) { $0 == "+" || $0 == "-" }
        // "cmd+-" splits into ["cmd", "", ""]: an empty last part is the minus key.
        for (i, part) in parts.enumerated() {
            if part.isEmpty, i > 0, i == parts.count - 1 { key = UInt16(kVK_ANSI_Minus); continue }
            switch part {
            case "ctrl", "control": modifiers.insert(.control)
            case "opt", "option", "alt": modifiers.insert(.option)
            case "cmd", "command", "super": modifiers.insert(.command)
            case "shift": modifiers.insert(.shift)
            case "": continue
            default:
                guard key == nil, let code = keyCodes[String(part)] else { return nil }
                key = code
            }
        }
        guard let key else { return nil }
        self.init(key, modifiers)
    }
}

private let keyCodes: [String: UInt16] = {
    var map: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
        "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
        "tab": kVK_Tab, "enter": kVK_Return, "return": kVK_Return, "esc": kVK_Escape, "escape": kVK_Escape,
        "space": kVK_Space, "backspace": kVK_Delete, "delete": kVK_Delete, "forwarddelete": kVK_ForwardDelete,
        "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
        "minus": kVK_ANSI_Minus, "equal": kVK_ANSI_Equal, "=": kVK_ANSI_Equal,
        "comma": kVK_ANSI_Comma, ",": kVK_ANSI_Comma, "period": kVK_ANSI_Period, ".": kVK_ANSI_Period,
        "slash": kVK_ANSI_Slash, "/": kVK_ANSI_Slash, "semicolon": kVK_ANSI_Semicolon, ";": kVK_ANSI_Semicolon,
        "quote": kVK_ANSI_Quote, "'": kVK_ANSI_Quote, "backslash": kVK_ANSI_Backslash, "\\": kVK_ANSI_Backslash,
        "grave": kVK_ANSI_Grave, "`": kVK_ANSI_Grave,
        "leftbracket": kVK_ANSI_LeftBracket, "[": kVK_ANSI_LeftBracket,
        "rightbracket": kVK_ANSI_RightBracket, "]": kVK_ANSI_RightBracket,
    ]
    let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
    for (i, code) in functionKeys.enumerated() { map["f\(i + 1)"] = code }
    return map.mapValues { UInt16($0) }
}()

/// What the tap consumes. Built on the main thread, swapped in whole.
public struct BindingTable: Equatable, Sendable {
    public var bindings: [Chord: Action]
    /// Consumed and dropped, so they never reach apps.
    public var swallow: Set<Chord>

    public init(bindings: [Chord: Action] = [:], swallow: Set<Chord> = BindingTable.optionNoOps) {
        self.bindings = bindings
        self.swallow = swallow
    }

    /// Phantomat's "do nothing on the canvas" keys in their AeroSpace
    /// positions: ⌥1-0, ⌥⇧1-0, ⌥/, ⌥, and ⌥; would otherwise type ¡™£.
    public static let optionNoOps: Set<Chord> = {
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                      kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0]
        var chords = Set(digits.flatMap { [Chord(UInt16($0), .option), Chord(UInt16($0), [.option, .shift])] })
        for key in [kVK_ANSI_Slash, kVK_ANSI_Comma, kVK_ANSI_Semicolon] { chords.insert(Chord(UInt16(key), .option)) }
        return chords
    }()

    /// Actions that fire again while their key is held.
    public static func repeats(_ action: Action) -> Bool {
        switch action {
        case .nudge, .switchWindow, .pan, .zoomIn, .zoomOut: true
        default: false
        }
    }
}

// MARK: - What the tap reports

public enum GesturePhase: Sendable, Equatable {
    case began, changed, ended
}

public struct KeyPress: Sendable, Equatable {
    public var keyCode: UInt16
    public var modifiers: Modifiers
    public var isRepeat: Bool
    /// What the key types with the current layout and modifiers.
    public var characters: String

    public init(keyCode: UInt16, modifiers: Modifiers, isRepeat: Bool = false, characters: String = "") {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isRepeat = isRepeat
        self.characters = characters
    }
}

/// Delivered on the main queue. Points are global, y-down.
public enum TapEvent: Sendable, Equatable {
    case action(Action, isRepeat: Bool)
    /// Key-capture mode: every unbound key. Switcher: Esc.
    case key(KeyPress)
    /// Modifier changes while the switcher is up (releasing ⌥ commits), or
    /// always with `reportsModifiers`.
    case modifiers(Modifiers)
    case pan(GesturePhase, CGPoint) // middle-button drag
    case move(GesturePhase, CGPoint) // move modifiers + left drag
    case resize(GesturePhase, CGPoint) // move modifiers + right drag
    case zoom(lines: Double, at: CGPoint) // zoom modifiers + wheel; positive = wheel up
    case magnify(Double, at: CGPoint) // pinch, only while the overview is open
}

/// Everything the tap callback reads. Set from the main thread.
public struct TapState: Equatable, Sendable {
    public var table = BindingTable()
    /// Overview fallback: consume every key the table does not bind and
    /// report it as `.key`.
    public var keyCapture = false
    /// The ⌥Tab strip is up: report modifier changes and Esc.
    public var switcher = false
    /// Pinch zooms only while the overview is open.
    public var overviewOpen = false
    /// Report every modifier change (the app warms captures on ⌃⌥ down).
    public var reportsModifiers = false
    /// Points a middle press travels before it pans instead of clicking.
    public var dragThreshold: Double = 10
    public var moveModifiers: Modifiers = [.control, .option]
    public var zoomModifiers: Modifiers = [.control, .option] // ⌃ alone is macOS's Accessibility Zoom gesture

    public init() {}
}

// MARK: - Routing, pure

/// One input event, already decoded from its CGEvent.
enum TapInput: Equatable {
    enum Mouse: Equatable { case down, dragged, up }

    case key(down: Bool, KeyPress)
    case flags(Modifiers)
    case mouse(Mouse, button: Int, at: CGPoint, modifiers: Modifiers) // 0 left, 1 right, 2 middle
    case scroll(lines: Double, at: CGPoint, modifiers: Modifiers)
    case magnify(Double, at: CGPoint)
}

struct TapOutput: Equatable {
    var consume = false
    var events: [TapEvent] = []
    /// A middle click that never became a pan, to post again.
    var replayMiddleClick = false
}

/// The tap's decisions. Lives on the tap thread; no system calls, so tests
/// drive it with synthetic input.
struct TapRouter {
    private var heldKeys: Set<UInt16> = []
    private var heldModifiers: Modifiers = []
    private var middle: (start: CGPoint, panning: Bool, last: CGPoint)?
    private var drag: (button: Int, last: CGPoint)? // 0 moves, 1 resizes
    /// Set by a switcher chord until its modifiers are released, so the
    /// release is reported even before the main thread sets `switcher`.
    private var switcherHeld: Modifiers = []

    mutating func route(_ input: TapInput, _ state: TapState) -> TapOutput {
        var out = TapOutput()
        switch input {
        case .key(let down, let press):
            guard down else {
                out.consume = heldKeys.remove(press.keyCode) != nil
                return out
            }
            let chord = Chord(press.keyCode, press.modifiers)
            let switcher = state.switcher || !switcherHeld.isEmpty
            if let action = state.table.bindings[chord] {
                out.consume = true
                if !press.isRepeat || BindingTable.repeats(action) {
                    out.events = [.action(action, isRepeat: press.isRepeat)]
                }
                if case .switchWindow = action { switcherHeld = press.modifiers.subtracting(.shift) }
            } else if state.table.swallow.contains(chord) {
                out.consume = true
            } else if state.keyCapture || (switcher && press.keyCode == UInt16(kVK_Escape)) {
                out.consume = true
                out.events = [.key(press)]
            }
            if out.consume { heldKeys.insert(press.keyCode) }

        case .flags(let modifiers):
            heldModifiers = modifiers
            if state.switcher || state.reportsModifiers || !switcherHeld.isEmpty { out.events = [.modifiers(modifiers)] }
            if !modifiers.isSuperset(of: switcherHeld) { switcherHeld = [] }

        case .mouse(let phase, 2, let point, _):
            switch phase {
            case .down:
                middle = (point, false, point)
                out.consume = true
            case .dragged:
                guard var m = middle else { return out }
                out.consume = true
                if m.panning {
                    out.events = [.pan(.changed, point)]
                } else if hypot(point.x - m.start.x, point.y - m.start.y) > state.dragThreshold {
                    m.panning = true
                    out.events = [.pan(.began, m.start), .pan(.changed, point)]
                }
                m.last = point
                middle = m
            case .up:
                guard let m = middle else { return out }
                middle = nil
                out.consume = true
                if m.panning { out.events = [.pan(.ended, point)] } else { out.replayMiddleClick = true }
            }

        case .mouse(let phase, let button, let point, let modifiers) where button < 2:
            switch phase {
            case .down:
                guard drag == nil, modifiers == state.moveModifiers else { return out }
                drag = (button, point)
                out.consume = true
                out.events = [gesture(button, .began, point)]
            case .dragged, .up:
                guard let d = drag, d.button == button else { return out }
                out.consume = true
                out.events = [gesture(button, phase == .up ? .ended : .changed, point)]
                drag = phase == .up ? nil : (button, point)
            }

        case .mouse:
            break

        case .scroll(let lines, let point, let modifiers):
            if modifiers == state.zoomModifiers, lines != 0 {
                out.consume = true
                out.events = [.zoom(lines: lines, at: point)]
            }

        case .magnify(let amount, let point):
            if state.overviewOpen {
                out.consume = true
                out.events = [.magnify(amount, at: point)]
            }
        }
        return out
    }

    /// Left and right buttons, the wheel and pinches matter only with the
    /// move or zoom modifiers held, during a modifier drag, or in the
    /// overview; the rest of the time they need not visit this process.
    func wantsPointer(_ state: TapState) -> Bool {
        drag != nil || state.overviewOpen || heldModifiers == state.moveModifiers || heldModifiers == state.zoomModifiers
    }

    /// The tap was switched off by the system: ends gestures in progress,
    /// since their button-up events are lost. `held` is what the keyboard
    /// holds now, so a ⌃⌥ still down keeps the pointer tap on.
    mutating func reset(held: Modifiers = []) -> [TapEvent] {
        var events: [TapEvent] = []
        if let m = middle, m.panning { events.append(.pan(.ended, m.last)) }
        if let d = drag { events.append(gesture(d.button, .ended, d.last)) }
        self = TapRouter()
        heldModifiers = held
        return events
    }

    private func gesture(_ button: Int, _ phase: GesturePhase, _ point: CGPoint) -> TapEvent {
        button == 0 ? .move(phase, point) : .resize(phase, point)
    }
}

// MARK: - Three-finger swipes

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

// MARK: - The tap

/// Two CGEventTaps at the head of the session, on their own thread and run
/// loop: keys, modifiers and the middle button always; left and right
/// buttons, the wheel and gestures only while `TapRouter.wantsPointer`, so
/// every click, drag and scroll in other apps does not make a round trip
/// through this process. The callback only routes; handlers run later on
/// the main queue.
public final class EventTap {
    /// eventSourceUserData of events we post ourselves, so the tap lets them through.
    public static let replayMarker: Int64 = 0x5048_414E // "PHAN"

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
        else { return swipeLog.error("no trackpad tap (Accessibility?)") }
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

/// The swipe tap's problems in the system log: `log show --predicate 'subsystem == "my.miel.mielwm"'`.
private let swipeLog = Logger(subsystem: "my.miel.mielwm", category: "swipe")
