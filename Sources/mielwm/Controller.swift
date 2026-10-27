import AppKit
import Carbon.HIToolbox
import MielCore
import MielRender
@preconcurrency import MielSystem
import QuartzCore

enum Mode: Equatable {
    case normal
    /// Tests: no event tap, no overlays, no menu, never takes focus; manages
    /// only this pid's windows and is driven over the socket.
    case manageOnly(Int32)

    var pid: Int32? { if case let .manageOnly(pid) = self { pid } else { nil } }
}

/// Owns Core's CanvasState and wires it to System (windows, keys, captures)
/// and Render (one overlay per display). Main thread only.
@MainActor
final class Controller {
    static let openBudget = 0.12 // seconds the overview waits for a fresh frame
    static let confirmBudget = 0.1 // seconds the landing waits for moves to be confirmed
    static let fadeDuration = 0.12
    static let streamLinger = 3.0 // seconds streams stay warm after the overlay hides
    static let purgeDelay = 30.0 // seconds after the overlay hides until its GPU memory goes
    static let shrinkDelay = 300.0 // seconds after the overlay hides until parked windows' stills shrink
    static let maxStreams = 12 // windows on screen past this get stills

    let mode: Mode
    let paths = ConfigPaths.standard()
    let layoutURL: URL
    private(set) var state: CanvasState
    private(set) var configErrors: [String]
    /// The menu refreshes on this.
    var onChange: (() -> Void)?
    /// The settings action (a shortcut or `mielwm settings`): the app opens its window.
    var onSettings: ((SettingsPane?) -> Void)? // nil: the last pane
    /// The menu bar's workspace numbers changed.
    var onWorkspaces: ((WorkspaceStatus) -> Void)?
    private var reportedWorkspaces: WorkspaceStatus?
    /// While the Settings window records a shortcut, every key reaches it.
    var bindingsSuspended = false {
        didSet {
            tapSettings = nil
            updateTap()
        }
    }

    let capture = CaptureManager()
    private var registry: WindowRegistry!
    private var tap: EventTap?
    private lazy var swipes = SwipeMonitor { [weak self] forward in MainActor.assumeIsolated { self?.swiped(forward: forward) } }
    private var tapState = TapState()
    private var tapSettings: Settings? // what bindingTable was built from
    private var bindingTable = BindingTable()
    private var heldModifiers: Modifiers = []
    private var warmModifiers: Set<Modifiers> = [] // held, they warm the captures: the overview's key is next
    private var ipc: IPCServer?
    private(set) var renderer: Renderer?
    private var overlays: [UInt32: Overlay] = [:]

    // Opening: inputs wait here until captures are fresh (see `input`).
    private var gate: (queue: [CoreInput], waitFor: WindowID?, opensOverview: Bool, timeout: DispatchWorkItem)?
    private var streamsLive = false
    private var coolWork: DispatchWorkItem?
    private var purgeWork: DispatchWorkItem?
    private var shrinkWork: DispatchWorkItem?

    // Overlay lifecycle: shown while Core needs it, then confirm, then fade.
    private var overlayShown = false
    private var worldShown = false // windows drawn (not just the ⌥Tab strip)
    private var restingSince: Double?
    private var fadeStart: Double?
    private var tickTimer: Timer?
    private var keyCaptureFallback = false

    // Pointer gestures.
    private var panLast: CGPoint?
    private var panSamples: [(time: Double, delta: CGVector)] = []
    private var tapDrag: (id: WindowID, corner: PointerGesture.Corner?, last: CGPoint)?
    private var mouse: (start: CGPoint, last: CGPoint, window: WindowID?, grab: CGPoint, dragging: Bool, screen: ScreenInfo)?

    // Files.
    private var savedLayoutRevision = 0
    private var savedLayout: LayoutSnapshot?
    private var saveWork: DispatchWorkItem?
    private var configStamp: [Date?] = []
    private var configWatcher: FileWatcher?
    private var wallpaperStamps: [UInt32: String] = [:]
    private var commandSerial: [WindowID: Int] = [:]
    private var tokens: [NSObjectProtocol] = []
    private var workspaceTokens: [NSObjectProtocol] = [] // on NSWorkspace's own notification center
    private var appearance: NSKeyValueObservation?

    init(mode: Mode) {
        self.mode = mode
        let loaded = loadSettings(paths)
        configErrors = loaded.errors
        layoutURL = mode == .normal ? LayoutSnapshot.standardURL()
            : FileManager.default.temporaryDirectory.appendingPathComponent("mielwm-manage-only-\(getpid())/layout.json")
        let saved = mode == .normal ? LayoutSnapshot.load(from: layoutURL) : nil
        state = CanvasState(screens: Displays.screens(), settings: loaded.settings, ownPID: getpid(),
                            now: CACurrentMediaTime(), savedLayout: saved)
        state.systemAccent = Self.systemAccent()
        state.systemDark = Self.systemDark()
        state.accessibility = Self.accessibility()
        state.stopwords = Self.stopwords()
        savedLayoutRevision = state.layoutRevision
        configStamp = stamps()
        for e in configErrors { log("config: \(e)") }
    }

    func start() {
        registry = WindowRegistry(pidFilter: mode.pid) { [weak self] event in
            MainActor.assumeIsolated { self?.system(event) }
        }
        // MIELWM_TEST_OVERLAY: manage-only draws the overlay too (it still never takes focus).
        if mode == .normal || ProcessInfo.processInfo.environment["MIELWM_TEST_OVERLAY"] != nil {
            do { renderer = try Renderer() } catch { log("no Metal renderer: \(error)") }
            renderer?.drawsCaret = false // the overlays blink it in a layer
            rebuildOverlays()
            capture.onFirstFrame = { [weak self] id in MainActor.assumeIsolated { self?.firstFrame(id) } }
        }
        if mode == .normal {
            let tap = EventTap { [weak self] event in MainActor.assumeIsolated { self?.tapEvent(event) } }
            if tap.start() { self.tap = tap } else { configErrors.append("Keyboard shortcuts need the Accessibility permission") }
            updateTap()
            let center = NotificationCenter.default
            tokens.append(center.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.state.systemAccent = Self.systemAccent() }
            })
            workspaceTokens.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.state.accessibility = Self.accessibility() }
            })
            appearance = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.state.systemDark = Self.systemDark() } }
            }
        }
        configWatcher = FileWatcher([paths.config]) { [weak self] in
            MainActor.assumeIsolated { self?.checkConfig() }
        }
        do {
            ipc = try IPCServer(path: socketPath) { [weak self] args, reply in
                MainActor.assumeIsolated { self?.command(args, reply) }
            }
        } catch {
            log("socket: \(error); `mielwm <action>` will not reach this instance")
        }
        registry.start()
    }

    /// Quit, toggle off, signals: every window back on a screen, then stop.
    func shutdown(_ done: @escaping () -> Void) {
        tap?.stop()
        tap = nil
        swipes.stop()
        configWatcher?.stop()
        tickTimer?.invalidate()
        tickTimer = nil
        gate?.timeout.cancel()
        gate = nil
        hideOverlays()
        for o in overlays.values { o.close() }
        overlays = [:]
        tokens.forEach(NotificationCenter.default.removeObserver)
        workspaceTokens.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        let commands = state.send(.unparkAll)
        saveNow()
        ipc?.stop()
        let registry = registry!, capture = capture
        let applied = registry.perform(commands) // on main: the registry's app list is main-only
        DispatchQueue.global(qos: .userInitiated).async {
            if applied.wait(timeout: .now() + 2) != .success { log("some windows did not answer in time") }
            // While quitting, AppKit runs the main run loop in modal-panel mode, which the main queue does not reach.
            RunLoop.main.perform(inModes: [.default, .modalPanel]) {
                registry.stop()
                capture.stop(dropFrames: true)
                done()
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
    }

    // MARK: Input

    /// Every input goes through here. One that would bring the overlay up
    /// while captures are cold waits (with what follows) until the focused
    /// window has a fresh frame or `openBudget` passes, so the first overlay
    /// frame is the desktop as it is.
    func input(_ input: CoreInput) {
        if case .tick = input { return apply(input) }
        if case .action(.settings) = input { // the overlay would sit above the window
            if state.isOverview { apply(.action(.back)) }
            onSettings?(nil)
            return
        }
        if gate != nil { gate!.queue.append(input); return }
        if renderer != nil, !overlayShown, !streamsLive, mayOpenOverlay(input) {
            var probe = state
            _ = probe.send(input)
            if probe.needsOverlay, showsWorld(probe) { return openGate(input, opensOverview: probe.isOverview) }
        }
        apply(input)
    }

    /// Reports, text and modifiers never bring the overlay up: no need to try them on a copy first.
    private func mayOpenOverlay(_ input: CoreInput) -> Bool {
        switch input {
        case .system(.windowFrameChanged), .system(.windowTitleChanged), .modifiersChanged, .text, .markedText: false
        default: true
        }
    }

    private func apply(_ input: CoreInput) {
        if case .tick = input {} else { step(.tick(CACurrentMediaTime())) } // Core's clock must be current
        step(input)
    }

    private func step(_ input: CoreInput) {
        let before = state
        let commands = state.send(input)
        perform(commands, before: before)
        let focusSent = commands.contains { if case .focus = $0 { true } else { false } }
        update(from: before, focusSent: focusSent)
    }

    private func perform(_ commands: [WindowCommand], before: CanvasState) {
        var now: [WindowCommand] = [], later: [(WindowID, WindowCommand, Int)] = []
        for c in commands {
            switch c {
            case .focus:
                if mode != .normal { continue } // tests never take the user's focus
                now.append(c)
            case let .setFrame(id, _):
                commandSerial[id, default: 0] += 1
                // Going to a park slot with no live stream: take a still first, so the overview has a picture.
                if renderer != nil, !streamsLive, state.window(id)?.parked == true, before.window(id)?.parked == false {
                    later.append((id, c, commandSerial[id]!))
                } else {
                    now.append(c)
                }
            }
        }
        if !now.isEmpty { registry.perform(now) }
        guard !later.isEmpty else { return }
        var done = false
        let finish = { [weak self] in
            guard let self, !done else { return }
            done = true
            // A newer command for the same window wins.
            self.registry.perform(later.filter { self.commandSerial[$0.0] == $0.2 }.map(\.1))
        }
        capture.captureStills(later.map(\.0), scale: stillScale) { MainActor.assumeIsolated { finish() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { MainActor.assumeIsolated { finish() } }
    }

    /// What follows every input: overlays, keyboard, tap, files, ticking.
    private func update(from before: CanvasState, focusSent: Bool) {
        if state.isOverview != before.isOverview {
            state.isOverview ? didOpenOverview() : didCloseOverview(focusSent: focusSent)
        }
        if state.appearanceRequests != before.appearanceRequests { onSettings?(.appearance) }
        if state.overview.switcher, !before.overview.switcher { warmStreams() }
        if renderer != nil {
            if state.needsOverlay {
                restingSince = nil
                fadeStart = nil
                worldShown = showsWorld(state)
                if !overlayShown { showOverlays() }
            } else if overlayShown, restingSince == nil, fadeStart == nil {
                restingSince = state.now
            }
        }
        updateTap()
        if state.layoutRevision != savedLayoutRevision { scheduleSave() }
        scheduleTicks()
        reportWorkspaces()
    }

    /// The overlay draws windows (not only the ⌥Tab strip over the real desktop).
    private func showsWorld(_ s: CanvasState) -> Bool {
        s.isOverview || s.isPanning || !s.animator.isSettled
    }

    // MARK: Captures

    private func openGate(_ input: CoreInput, opensOverview: Bool) {
        warmStreams()
        let waitFor = state.focused.flatMap { f in state.window(f).flatMap { $0.isShown && !$0.parked ? f : nil } }
        let timeout = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.closeGate() } }
        gate = ([input], waitFor, opensOverview, timeout)
        updateTap() // keys typed meanwhile wait in the gate too
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.openBudget, execute: timeout)
    }

    private func closeGate() {
        guard let g = gate else { return }
        g.timeout.cancel()
        gate = nil
        g.queue.forEach(input)
        updateTap()
    }

    private func firstFrame(_ id: WindowID) {
        if let g = gate, g.waitFor == nil || g.waitFor == id { closeGate() }
    }

    /// Live streams for the windows on screen (the focused and largest
    /// first, at most `maxStreams`), fresh stills for the rest.
    /// Called on the overview chord's modifiers, ⌥Tab and before the overlay opens.
    private func warmStreams() {
        guard renderer != nil else { return }
        coolWork?.cancel()
        coolWork = nil
        capture.setRate(.overview)
        let onScreen = state.windows.filter { $0.isShown && !$0.parked }.sorted {
            ($0.id == state.focused ? 1 : 0, $0.real.width * $0.real.height) > ($1.id == state.focused ? 1 : 0, $1.real.width * $1.real.height)
        }
        for w in onScreen.prefix(Self.maxStreams) {
            let scale = screenShowingMost(w.real, of: state.screens)?.scale ?? 2
            capture.warm([w.id], maxPixelSize: CGSize(width: w.real.width * scale, height: w.real.height * scale))
        }
        if !streamsLive {
            capture.captureStills(state.windows.filter { $0.isShown && $0.parked }.map(\.id) + onScreen.dropFirst(Self.maxStreams).map(\.id),
                                  scale: stillScale)
        }
        streamsLive = true
        if !overlayShown { scheduleCool() }
    }

    private func scheduleCool() {
        coolWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.overlayShown, self.gate == nil else { return }
                self.capture.cool(stillScale: self.stillScale) // small stills of the last frames stay for next time
                self.capture.setRate(.idle)
                self.streamsLive = false
            }
        }
        coolWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.streamLinger, execute: work)
    }

    /// Stills at the size the overview draws them.
    private var stillScale: CGFloat { min(1, max(0.5, state.settings.initialZoom)) }

    // MARK: Overlays

    func rebuildOverlays() {
        guard let renderer else { return }
        let ids = Set(state.screens.map(\.id))
        for (id, o) in overlays where !ids.contains(id) {
            o.close()
            overlays[id] = nil
        }
        for s in state.screens {
            let o = overlays[s.id] ?? Overlay(screenID: s.id, controller: self, device: renderer.device)
            overlays[s.id] = o
            o.place(on: s)
            renderer.invalidate(screenID: s.id)
            if overlayShown { o.show(key: false) }
        }
        loadWallpapers()
        updateMouse()
    }

    /// Each display's desktop picture, read again only when it is another
    /// file or the file changed (dynamic ones, captured, every time).
    private func loadWallpapers() {
        guard renderer != nil else { return }
        for s in state.screens {
            let url = NSScreen.screens.first { $0.displayID == s.id }.flatMap(NSWorkspace.shared.desktopImageURL(for:))
            let date = url.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            let stamp = url.flatMap { $0.pathExtension.lowercased() == "heic" ? nil : "\($0.path) \(date?.timeIntervalSince1970 ?? 0) \(s.frame.size) \(s.scale)" }
            if let stamp, wallpaperStamps[s.id] == stamp { continue }
            wallpaperStamps[s.id] = stamp
            MielSystem.Wallpaper.image(for: s) { [weak self] image in MainActor.assumeIsolated { self?.setWallpaper(image, on: s) } }
        }
    }

    /// Sets the wallpaper and prepares it (scaled, blurred), so the first
    /// frame of the overview does not pay for that.
    private func setWallpaper(_ image: CGImage?, on screen: ScreenInfo) {
        guard let renderer else { return }
        renderer.setWallpaper(image, screenID: screen.id)
        renderer.prepare(state.scene(for: screen))
    }

    /// Once the overlay has been hidden a while: its GPU memory goes, made
    /// again on the next frame; later the stills of parked windows shrink.
    private func schedulePurge() {
        purgeWork?.cancel()
        shrinkWork?.cancel()
        let purge = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.overlayShown, self.gate == nil else { return }
                self.renderer?.purge()
                for o in self.overlays.values { o.dropDrawables() }
            }
        }
        let shrink = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.overlayShown, self.gate == nil, !self.streamsLive else { return }
                self.capture.shrinkStills(self.state.windows.filter(\.parked).map(\.id))
            }
        }
        purgeWork = purge
        shrinkWork = shrink
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.purgeDelay, execute: purge)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.shrinkDelay, execute: shrink)
    }

    private func showOverlays() {
        overlayShown = true
        coolWork?.cancel()
        purgeWork?.cancel()
        shrinkWork?.cancel()
        for o in overlays.values { o.show(key: state.isOverview && o.screenID == state.activeScreen.id) }
        updateMouse()
    }

    private func hideOverlays() {
        overlayShown = false
        restingSince = nil
        fadeStart = nil
        for o in overlays.values {
            o.hide()
            renderer?.invalidate(screenID: o.screenID) // shown again, it starts with a fresh frame
        }
        if streamsLive {
            capture.setRate(.linger) // fresh enough should it open again, a quarter of the work
            scheduleCool()
        }
        schedulePurge()
        scheduleTicks()
    }

    private func updateMouse() {
        // Open, the overview catches the pointer even when it ignores clicks, so none land on windows behind it.
        for o in overlays.values { o.window.ignoresMouseEvents = !state.isOverview }
    }

    /// One display link frame of one overlay: tick Core, then draw.
    func frame(screenID: UInt32) {
        let now = CACurrentMediaTime()
        if now - state.now > 0.0005 { input(.tick(now)) }
        guard overlayShown else { return }
        if let rest = restingSince, !state.movesInFlight || now - rest > Self.confirmBudget {
            restingSince = nil
            fadeStart = now
        }
        var opacity = 1.0
        if let fade = fadeStart {
            opacity = 1 - (now - fade) / Self.fadeDuration
            if opacity <= 0 { return hideOverlays() }
        }
        guard let renderer, let overlay = overlays[screenID], let screen = screen(id: screenID) else { return }
        var scene = state.scene(for: screen, time: now)
        if !worldShown {
            scene.windows = []
            scene.dropIndicator = nil
        }
        scene.opacity = opacity
        overlay.draw(scene, renderer: renderer, frames: capture)
    }

    /// Ticks without an overlay (moves awaiting confirmation, the switcher's delay).
    private func scheduleTicks() {
        let wanted = !overlayShown && state.needsTicks
        if wanted, tickTimer == nil {
            tickTimer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.input(.tick(CACurrentMediaTime())) }
            }
            RunLoop.main.add(tickTimer!, forMode: .common)
        } else if !wanted, let t = tickTimer {
            t.invalidate()
            tickTimer = nil
        }
    }

    private func didOpenOverview() {
        guard renderer != nil, mode == .normal else { return }
        NSApp.activate(ignoringOtherApps: true)
        overlays[state.activeScreen.id]?.show(key: true)
        updateMouse()
        // If macOS refuses to activate us, the tap types for the overview instead.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.state.isOverview, !NSApp.isActive else { return }
                self.keyCaptureFallback = true
                self.updateTap()
            }
        }
    }

    private func didCloseOverview(focusSent: Bool) {
        keyCaptureFallback = false
        updateMouse()
        // Esc lands nowhere: give the keyboard back to the window that had it.
        if !focusSent, mode == .normal, let f = state.focused { registry.perform([.focus(f)]) }
    }

    // MARK: System and the event tap

    private func system(_ event: SystemEvent) {
        if case let .windowClosed(id) = event { capture.stop([id], dropFrames: true) }
        input(.system(event))
        if case .screensChanged = event { rebuildOverlays() }
    }

    private func updateTap() {
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

    private func tapEvent(_ event: TapEvent) {
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
    private func swiped(forward: Bool) {
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

    private func velocity(_ now: Double) -> CGVector {
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
    private func zoomFactor(lines: Double) -> CGFloat {
        exp(state.settings.zoomStep * lines * state.settings.scrollFactor)
    }

    // MARK: Overlay input (the overview has the keyboard and the mouse)

    func overlayMouseDown(_ p: CGPoint, screenID: UInt32) {
        mouse = nil
        guard state.settings.pointer, let screen = screen(id: screenID) else { return }
        if state.look.minimapEnabled, let hit = state.minimapLayout(for: screen).hit(p) {
            switch hit {
            case .arrange: input(.action(.arrange))
            case let .jump(c): input(.gesture(.minimapJump(c)))
            }
            return
        }
        mouse = (p, p, state.window(atScreenPoint: p, on: screen), state.canvasPoint(atScreenPoint: p, on: screen), false, screen)
    }

    func overlayMouseDragged(_ p: CGPoint) {
        guard var m = mouse else { return }
        if !m.dragging, hypot(p.x - m.start.x, p.y - m.start.y) > state.settings.dragThreshold {
            m.dragging = true
            panSamples = []
        }
        if m.dragging {
            let now = CACurrentMediaTime()
            let zoom = state.camera.zoom
            let here = state.canvasPoint(atScreenPoint: p, on: m.screen)
            if let id = m.window {
                // Through the lens: the window stays under the pointer even near the edges.
                let before = state.canvasPoint(atScreenPoint: m.last, on: m.screen)
                input(.gesture(.dragWindow(id, CGVector(dx: (here.x - before.x) * zoom, dy: (here.y - before.y) * zoom))))
            } else {
                // The grabbed canvas point stays under the pointer.
                let k = zoom / max(state.settings.panSensitivity, 0.01)
                input(.gesture(.pan(CGVector(dx: (here.x - m.grab.x) * k, dy: (here.y - m.grab.y) * k))))
                panSamples.append((now, CGVector(dx: p.x - m.last.x, dy: p.y - m.last.y)))
            }
        }
        m.last = p
        mouse = m
    }

    /// Hover picks the window under the pointer, as in Mission Control; the camera stays.
    func overlayMouseMoved(_ p: CGPoint, screenID: UInt32) {
        guard state.settings.pointer, mouse == nil, let screen = screen(id: screenID), let id = state.window(atScreenPoint: p, on: screen),
              id != state.selection else { return }
        input(.select(id))
    }

    func overlayMouseUp(_ p: CGPoint) {
        guard let m = mouse else { return }
        mouse = nil
        if !m.dragging {
            if let id = m.window { input(.landOn(id)) }
        } else if let id = m.window {
            input(.gesture(.dragEnded(id)))
        } else {
            input(.gesture(.panEnded(velocity: velocity(CACurrentMediaTime()))))
        }
    }

    /// Trackpad scrolling pans, the canvas following the fingers 1:1 where
    /// the pointer is (momentum included: macOS sends it as more scrolling).
    /// A mouse wheel, or ⌘ or ⌃ held, zooms around the pointer.
    func overlayScroll(_ p: CGPoint, screenID: UInt32, delta: CGVector, precise: Bool, zoom: Bool) {
        guard state.settings.pointer, let screen = screen(id: screenID) else { return }
        let desk = state.deskPoint(atScreenPoint: p, on: screen)
        if precise, !zoom {
            let a = state.canvasPoint(atScreenPoint: p, on: screen)
            let b = state.canvasPoint(atScreenPoint: CGPoint(x: p.x + delta.dx, y: p.y + delta.dy), on: screen)
            let k = state.camera.zoom / max(state.settings.panSensitivity, 0.01)
            return input(.gesture(.pan(CGVector(dx: (b.x - a.x) * k, dy: (b.y - a.y) * k))))
        }
        // Wheels move in lines; trackpads in points, about ten to a line.
        if precise { return input(.gesture(.pinch(at: desk, factor: zoomFactor(lines: delta.dy / 10)))) }
        if delta.dy != 0 { input(.gesture(.zoom(at: desk, factor: zoomFactor(lines: delta.dy)))) }
    }

    func overlayMagnify(_ p: CGPoint, screenID: UInt32, magnification: Double) {
        guard state.settings.pointer, let screen = screen(id: screenID) else { return }
        input(.gesture(.pinch(at: state.deskPoint(atScreenPoint: p, on: screen), factor: 1 + magnification)))
    }

    // MARK: Geometry helpers

    private func screen(id: UInt32) -> ScreenInfo? {
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

    // MARK: Files

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.saveNow() } }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// layout.json, also what the crash watcher unparks from.
    func saveNow() {
        saveWork?.cancel()
        if state.layoutRevision != savedLayoutRevision {
            let snapshot = LayoutSnapshot(state)
            do {
                if snapshot != savedLayout { try snapshot.save(to: layoutURL) } // a move and back is no change
                savedLayout = snapshot
                savedLayoutRevision = state.layoutRevision
            } catch { log("cannot save the layout: \(error)") }
        }
    }

    private func stamps() -> [Date?] {
        [paths.config].map { (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date }
    }

    private func checkConfig() {
        let now = stamps()
        guard now != configStamp else { return }
        configStamp = now
        reloadConfig()
    }

    func reloadConfig() {
        let loaded = loadSettings(paths)
        configStamp = stamps()
        configErrors = loaded.errors
        for e in configErrors { log("config: \(e)") }
        if loaded.settings != state.settings { input(.setSettings(loaded.settings)) }
        updateMouse()
        loadWallpapers()
        onChange?()
    }

    // MARK: The menu bar and the Settings window

    /// What the menu bar shows: the workspaces with windows, and the current one with its layout.
    struct WorkspaceStatus: Equatable {
        var numbers: [Int]
        var current: Int?
        var mode: LayoutMode?
    }

    var workspaceStatus: WorkspaceStatus {
        let current = state.currentWorkspace.flatMap { $0 <= 9 ? $0 : nil }
        let numbers = Set(state.workspaces.filter { !$0.members.isEmpty }.compactMap(\.number) + (current.map { [$0] } ?? []))
        return WorkspaceStatus(numbers: numbers.sorted(), current: current, mode: state.workspaces.first { $0.slot == current }?.mode)
    }

    private func reportWorkspaces() {
        guard let onWorkspaces else { return }
        let status = workspaceStatus
        guard status != reportedWorkspaces else { return }
        reportedWorkspaces = status
        onWorkspaces(status)
    }

    /// The Settings window's values while they change (a slider moving), before config.json has them.
    func applyLive(_ settings: Settings) {
        if settings != state.settings { input(.setSettings(settings)) }
    }

    // MARK: Socket commands

    private func command(_ args: [String], _ reply: @escaping (Data) -> Void) {
        let text = args.joined(separator: " ")
        switch text {
        case "state":
            reply(stateJSON())
        case "quit":
            reply(Data(#"{"ok":true}"#.utf8))
            DispatchQueue.main.async { NSApp.terminate(nil) }
        default:
            guard let action = Action(command: text) else {
                return reply(Data(#"{"error":"unknown action"}"#.utf8))
            }
            input(.action(action))
            reply(Data(#"{"ok":true}"#.utf8))
        }
    }

    func stateJSON() -> Data {
        struct Window: Encodable {
            var id: String, app: String, title: String, frame: [Double], real: [Double]
            var parked: Bool, pinned: Bool, minimized: Bool, hidden: Bool
        }
        struct Dump: Encodable {
            var overview: Bool, zoom: Double, camera: [Double], deskCamera: [Double]
            var focused: String?, selection: String?, windows: [Window], screens: [String]
        }
        func r(_ f: CGRect) -> [Double] { [f.minX, f.minY, f.width, f.height] }
        let s = state
        let dump = Dump(overview: s.isOverview, zoom: s.camera.zoom, camera: [s.camera.center.x, s.camera.center.y],
                        deskCamera: [s.deskCamera.center.x, s.deskCamera.center.y],
                        focused: s.focused?.description, selection: s.selection?.description,
                        windows: s.windows.map {
                            Window(id: $0.id.description, app: $0.appName, title: $0.title, frame: r($0.frame), real: r($0.real),
                                   parked: $0.parked, pinned: $0.pinned != nil, minimized: $0.isMinimized, hidden: $0.isHidden)
                        },
                        screens: s.screens.map(\.name))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(dump)) ?? Data("{}".utf8)
    }

    // MARK: Small things

    /// Keys the overview and switcher understand; nil for typed text.
    static func namedKey(keyCode: UInt16, characters: String, modifiers: Modifiers) -> NamedKey? {
        switch Int(keyCode) {
        case kVK_LeftArrow: return .arrow(.left)
        case kVK_RightArrow: return .arrow(.right)
        case kVK_DownArrow: return .arrow(.down)
        case kVK_UpArrow: return .arrow(.up)
        case kVK_Tab: return .tab
        case kVK_Return, kVK_ANSI_KeypadEnter: return .enter
        case kVK_Escape: return .escape
        case kVK_F1: return .f1
        case kVK_Delete: return .backspace
        case kVK_ForwardDelete: return .forwardDelete
        default: break
        }
        guard modifiers.contains(.control) || modifiers.contains(.command) else { return nil }
        let digits = [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        if let n = digits.firstIndex(of: Int(keyCode)) { return .digit(n) }
        if Int(keyCode) == kVK_ANSI_Equal { return .equals }
        if Int(keyCode) == kVK_ANSI_Minus { return .minus }
        return characters.isEmpty ? nil : .character(characters.lowercased())
    }

    static func systemAccent() -> RGB? {
        NSColor.controlAccentColor.usingColorSpace(.sRGB).map { RGB(Double($0.redComponent), Double($0.greenComponent), Double($0.blueComponent)) }
    }

    /// Reduce Motion, Reduce Transparency and Increase Contrast from System Settings › Accessibility › Display.
    static func accessibility() -> AccessibilityOptions {
        let w = NSWorkspace.shared
        return AccessibilityOptions(reduceMotion: w.accessibilityDisplayShouldReduceMotion,
                                    reduceTransparency: w.accessibilityDisplayShouldReduceTransparency,
                                    increaseContrast: w.accessibilityDisplayShouldIncreaseContrast)
    }

    static func systemDark() -> Bool {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// The user and host names, so the tidy-up does not group windows by them.
    static func stopwords() -> Set<String> {
        var host = [CChar](repeating: 0, count: 256)
        gethostname(&host, host.count)
        let words = [NSUserName(), String(cString: host)].flatMap { $0.lowercased().split { !$0.isLetter && !$0.isNumber } }
        return Set(words.map(String.init).filter { $0.count > 1 && $0 != "local" })
    }
}

/// `MIELWM_SOCKET` moves the socket (tests run beside a real instance).
var socketPath: String { ProcessInfo.processInfo.environment["MIELWM_SOCKET"] ?? IPC.socketPath }

func log(_ message: String) {
    FileHandle.standardError.write(Data("mielwm: \(message)\n".utf8))
}
