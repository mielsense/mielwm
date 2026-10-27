import AppKit
import MielCore
import MielIPC
import MielRender
@preconcurrency import MielSystem
import QuartzCore

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
    var state: CanvasState
    var configErrors: [String]
    /// The menu refreshes on this.
    var onChange: (() -> Void)?
    /// The settings action (a shortcut or `mielwm settings`): the app opens its window.
    var onSettings: ((SettingsPane?) -> Void)? // nil: the last pane
    /// The menu bar's workspace numbers changed.
    var onWorkspaces: ((WorkspaceStatus) -> Void)?
    var reportedWorkspaces: WorkspaceStatus?
    /// While the Settings window records a shortcut, every key reaches it.
    var bindingsSuspended = false {
        didSet {
            tapSettings = nil
            updateTap()
        }
    }

    let capture = CaptureManager()
    var registry: WindowRegistry!
    var tap: EventTap?
    lazy var swipes = SwipeMonitor { [weak self] forward in MainActor.assumeIsolated { self?.swiped(forward: forward) } }
    var tapState = TapState()
    var tapSettings: Settings? // what bindingTable was built from
    var bindingTable = BindingTable()
    var heldModifiers: Modifiers = []
    var warmModifiers: Set<Modifiers> = [] // held, they warm the captures: the overview's key is next
    private var ipc: IPCServer?
    private(set) var renderer: Renderer?
    var overlays: [UInt32: Overlay] = [:]

    // Opening: inputs wait here until captures are fresh (see `input`).
    var gate: (queue: [CoreInput], waitFor: WindowID?, opensOverview: Bool, timeout: DispatchWorkItem)?
    var streamsLive = false
    var coolWork: DispatchWorkItem?
    var purgeWork: DispatchWorkItem?
    var shrinkWork: DispatchWorkItem?

    // Overlay lifecycle: shown while Core needs it, then confirm, then fade.
    var overlayShown = false
    var worldShown = false // windows drawn (not just the ⌥Tab strip)
    var restingSince: Double?
    var fadeStart: Double?
    var tickTimer: Timer?
    var keyCaptureFallback = false

    // Pointer gestures.
    var panLast: CGPoint?
    var panSamples: [(time: Double, delta: CGVector)] = []
    var tapDrag: (id: WindowID, corner: PointerGesture.Corner?, last: CGPoint)?
    var mouse: (start: CGPoint, last: CGPoint, window: WindowID?, grab: CGPoint, dragging: Bool, screen: ScreenInfo)?

    // Files.
    var savedLayoutRevision = 0
    var savedLayout: LayoutSnapshot?
    var saveWork: DispatchWorkItem?
    var configStamp: Date?
    private var configWatcher: FileWatcher?
    var wallpaperStamps: [UInt32: String] = [:]
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
        configStamp = paths.configModified
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
            ipc = try IPCServer() { [weak self] args, reply in
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
}
