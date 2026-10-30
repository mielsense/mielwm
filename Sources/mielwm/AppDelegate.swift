import AppKit
import MielCore
import MielSystem

/// The menu bar app: permissions, AeroSpace, pausing and resuming the canvas,
/// quitting with every window back on a screen.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let mode: Mode
    var controller: Controller?
    var statusItem: NSStatusItem?
    private var watcher: Process?
    var stopping = false // a shutdown is unparking windows
    private var quitWhenStopped = false
    private var signals: [DispatchSourceSignal] = []
    var aeroSpaceToken: NSObjectProtocol? // set while waiting for AeroSpace to quit
    var waitingForAeroSpace: Bool { aeroSpaceToken != nil }
    var onboarding: Onboarding?
    private var onboardingDone = false // Continue without Screen Recording: don't ask again this run
    var settingsWindow: SettingsWindow?
    var importNote: String? // a first-launch AeroSpace import, told once
    lazy var barik: BarikLink? = Self.makeBarikLink()

    init(mode: Mode) {
        self.mode = mode
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        for sig in [SIGINT, SIGTERM, SIGHUP] { // same path as Quit: unpark, then exit
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signals.append(source)
        }
        if mode == .normal {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.menu = NSMenu()
            item.menu?.delegate = self
            statusItem = item
            refreshIcon()
            importNote = importAeroSpaceOnFirstLaunch()
            if loadSettings(.standard()).settings.barik { barik?.resume() }
        }
        begin()
        if let note = takeImportNote() { showImportNotice(note) }
    }

    /// Starts the canvas once nothing stands in the way.
    func begin() {
        if mode == .normal {
            if !Permissions.accessibility() || (!Permissions.screenRecording() && !onboardingDone) { return showOnboarding() }
            if AeroSpace.running() != nil { return askAboutAeroSpace() }
            noticeSeparateSpaces()
        }
        startCanvas()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard controller != nil || stopping else { return .terminateNow }
        quitWhenStopped = true // also waits for a toggle-off still unparking
        stopCanvas()
        return .terminateLater
    }

    // MARK: - Canvas on and off

    private func startCanvas() {
        guard controller == nil, !stopping else { return }
        let c = Controller(mode: mode)
        c.onChange = { [weak self] in self?.refreshIcon() }
        c.onWorkspaces = { [weak self] in self?.refreshIcon() }
        c.onSettings = { [weak self] pane in self?.showSettings(at: pane) }
        c.onScreens = { [weak self] in self?.settingsWindow?.model.refreshScreens() }
        c.bindingsSuspended = settingsWindow?.model.recording != nil
        controller = c
        c.start()
        if mode == .normal { startWatcher() }
        refreshIcon()
    }

    func stopCanvas() {
        guard let c = controller else { return }
        controller = nil
        stopping = true
        c.shutdown(quitting: quitWhenStopped) { [weak self] answered in
            guard let self else { return }
            stopping = false
            // Quitting while an app did not answer: the watcher unparks its
            // windows from layout.json once this process exits.
            if answered || !quitWhenStopped { stopWatcher() } else { watcher = nil }
            refreshIcon()
            if quitWhenStopped { NSApp.reply(toApplicationShouldTerminate: true) }
        }
    }

    /// `mielwm --watch <pid>` unparks every window from layout.json if
    /// this process dies without the clean exit (which stops it first).
    private func startWatcher() {
        guard let exe = Bundle.main.executableURL else { return }
        let p = Process()
        p.executableURL = exe
        p.arguments = ["--watch", String(getpid())]
        do {
            try p.run()
            watcher = p
        } catch { log("crash watcher did not start: \(error)") }
    }

    private func stopWatcher() {
        watcher?.terminate()
        watcher = nil
    }

    // MARK: - Permissions

    private func showOnboarding() {
        guard onboarding == nil else { return }
        let onboarding = Onboarding(note: takeImportNote()) { [weak self] in
            guard let self else { return }
            self.onboarding = nil
            onboardingDone = true
            // Closed before Accessibility was allowed: mielwm stays paused, and Resume asks again.
            if Permissions.accessibility() { begin() } else { refreshIcon() }
        }
        self.onboarding = onboarding
        onboarding.show()
        refreshIcon()
    }
}
