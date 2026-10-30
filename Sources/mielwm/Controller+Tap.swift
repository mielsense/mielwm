import AppKit
import MielCore
import MielRender
import MielSystem
import QuartzCore

extension Controller {
    func system(_ event: SystemEvent) {
        if case let .windowClosed(id) = event { capture.stop([id], dropFrames: true) }
        input(.system(event))
        if case .screensChanged = event {
            rebuildOverlays()
            onScreens?()
        }
    }

    func updateTap() {
        guard let tap else { return }
        var t = tapState
        let s = state.settings
        let wantsSwipes = s.swipeWorkspaces && !bindingsSuspended // only with the shortcuts: normal mode
        if wantsSwipes != swipes.isOn { wantsSwipes ? swipes.start() : swipes.stop() }
        if tapSettings != s { // the binding table only changes with the settings
            tapSettings = s
            var bindings: [Chord: Action] = [:], swallow: Set<Chord> = [] // only the config's no-ops: a key the user unbinds types again
            for (chord, action) in s.chords {
                guard let c = Chord(chord.description) else { continue }
                if action == .noop { swallow.insert(c) } else { bindings[c] = action }
            }
            bindingTable = BindingTable(bindings: bindings, swallow: swallow)
            warmModifiers = s.warmModifiers
            t.dragThreshold = s.dragThreshold
            t.moveModifiers = s.moveModifiers
        }
        t.table = bindingTable
        // The overview uses ⌃-arrows to pan: the workspace keys step aside there.
        if state.isOverview { t.table.bindings = t.table.bindings.filter { if case .workspaceStep = $0.value { false } else { true } } }
        if bindingsSuspended { t.table = BindingTable(bindings: [:], swallow: []) }
        t.switcher = state.overview.switcher && !state.isOverview
        t.overviewOpen = state.isOverview
        t.keyCapture = (state.isOverview && keyCaptureFallback) || (gate?.opensOverview ?? false)
        t.reportsModifiers = true
        if t != tapState {
            tapState = t
            tap.state = t
        }
    }

    func tapEvent(_ event: TapEvent) {
        switch event {
        case let .action(action, _):
            if !state.isOverview { state.activeScreenID = screenUnderMouse()?.id }
            input(.action(action))
        case let .key(press):
            if let key = Self.namedKey(keyCode: press.keyCode, characters: press.characters, modifiers: press.modifiers) {
                input(.key(key, press.modifiers))
            } else if !press.characters.isEmpty, press.modifiers.isDisjoint(with: [.control, .command]) {
                input(.text(press.characters))
            }
        case let .modifiers(mods):
            if mods != heldModifiers, warmModifiers.contains(mods), !state.isOverview { warmStreams() } // the key is ~100 ms away
            heldModifiers = mods
            if state.overview.switcher { input(.modifiersChanged(mods)) } // only the switcher cares
        case let .pan(phase, p): pan(phase, p)
        case let .move(phase, p): tapDrag(phase, p, resize: false)
        case let .resize(phase, p): tapDrag(phase, p, resize: true)
        case let .zoom(lines, p): input(.gesture(.zoom(at: deskPoint(p), factor: zoomFactor(lines: lines))))
        case let .magnify(m, p): input(.gesture(.pinch(at: deskPoint(p), factor: 1 + m)))
        }
    }

    /// Three fingers sideways: the next or previous workspace.
    func swiped(forward: Bool) {
        let before = state.currentWorkspace
        input(.action(.workspaceStep(forward: forward)))
        // A click through the Force Touch trackpad, like a Spaces swipe; none at the last workspace.
        if state.currentWorkspace != before { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
    }

    /// Middle drag, anywhere: the canvas follows the pointer, with momentum on release.
    private func pan(_ phase: GesturePhase, _ p: CGPoint) {
        let now = CACurrentMediaTime()
        switch phase {
        case .began:
            panLast = p
            panSamples = []
        case .changed:
            guard let last = panLast else { return }
            let d = CGVector(dx: p.x - last.x, dy: p.y - last.y)
            panLast = p
            panSamples.append((now, d))
            input(.gesture(.pan(d)))
        case .ended:
            panLast = nil
            input(.gesture(.panEnded(velocity: velocity(now))))
        }
    }

    func velocity(_ now: Double) -> CGVector {
        let recent = panSamples.filter { now - $0.time < 0.08 }
        panSamples = []
        guard let first = recent.first, now - first.time > 0.005 else { return .zero }
        let dt = max(now - first.time, 1.0 / 120)
        return CGVector(dx: recent.reduce(0) { $0 + $1.delta.dx } / dt, dy: recent.reduce(0) { $0 + $1.delta.dy } / dt)
    }

    /// Move-modifier drags: left moves, right resizes from the nearest corner.
    private func tapDrag(_ phase: GesturePhase, _ p: CGPoint, resize: Bool) {
        switch phase {
        case .began:
            guard let id = windowAt(global: p), let w = state.window(id) else { return tapDrag = nil }
            var corner: PointerGesture.Corner?
            if resize {
                let c = canvasPoint(global: p), f = w.frame
                corner = c.x < f.midX ? (c.y < f.midY ? .topLeft : .bottomLeft) : (c.y < f.midY ? .topRight : .bottomRight)
            }
            tapDrag = (id, corner, p)
        case .changed:
            guard let d = tapDrag else { return }
            let delta = deskDelta(from: d.last, to: p)
            tapDrag?.last = p
            input(.gesture(d.corner.map { .resizeWindow(d.id, $0, delta) } ?? .dragWindow(d.id, delta)))
        case .ended:
            guard let d = tapDrag else { return }
            tapDrag = nil
            input(.gesture(.dragEnded(d.id)))
        }
    }

    /// Wheel lines (positive: up, zoom in) as a zoom factor.
    func zoomFactor(lines: Double) -> CGFloat {
        exp(state.settings.zoomStep * lines * state.settings.scrollFactor)
    }

    // MARK: Geometry helpers

    func screen(id: UInt32) -> ScreenInfo? {
        state.screens.first { $0.id == id }
    }

    private func screenAt(global p: CGPoint) -> ScreenInfo? {
        state.screens.first { $0.frame.contains(p) }
    }

    private func screenUnderMouse() -> ScreenInfo? {
        let m = NSEvent.mouseLocation, primary = NSScreen.screens.first?.frame.height ?? 0
        return screenAt(global: CGPoint(x: m.x, y: primary - m.y))
    }

    /// The desk point the lens shows at a global screen point.
    private func deskPoint(_ p: CGPoint) -> CGPoint {
        guard let s = screenAt(global: p) else { return p }
        return state.deskPoint(atScreenPoint: CGPoint(x: p.x - s.frame.minX, y: p.y - s.frame.minY), on: s)
    }

    private func canvasPoint(global p: CGPoint) -> CGPoint {
        state.camera.toCanvas(deskPoint(p), deskCenter: state.deskCenter)
    }

    /// A pointer move in desk points (through the lens while zoomed out).
    private func deskDelta(from a: CGPoint, to b: CGPoint) -> CGVector {
        let ca = canvasPoint(global: a), cb = canvasPoint(global: b), z = state.camera.zoom
        return CGVector(dx: (cb.x - ca.x) * z, dy: (cb.y - ca.y) * z)
    }

    /// Zoomed out: the canvas window under the point. At 100%: the frontmost
    /// real window there, if mielwm manages it.
    private func windowAt(global p: CGPoint) -> WindowID? {
        if state.isOverview, let s = screenAt(global: p) {
            return state.window(atScreenPoint: CGPoint(x: p.x - s.frame.minX, y: p.y - s.frame.minY), on: s)
        }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list where (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.contains(p),
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let number = info[kCGWindowNumber as String] as? UInt32 else { continue }
            let id = WindowID(pid: pid, number: number)
            return state.window(id) != nil ? id : nil // an unmanaged window on top is not grabbed through
        }
        return nil
    }
}
