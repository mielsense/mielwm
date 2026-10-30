import Carbon.HIToolbox
import CoreGraphics
import MielCore

/// One input event, already decoded from its CGEvent.
enum TapInput: Equatable {
    enum Mouse: Equatable { case down, dragged, up }

    case key(down: Bool, KeyPress)
    case flags(Modifiers)
    case mouse(Mouse, button: Int, at: CGPoint, modifiers: Modifiers) // 0 left, 1 right, 2 middle
    case scroll(lines: Double, at: CGPoint, modifiers: Modifiers)
    case magnify(Double, at: CGPoint)
}

/// What the router decided: whether to swallow the event, and what to tell the app.
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
