import AppKit
import MielCore
import MielSystem

/// The menu bar app: permissions, AeroSpace, pausing and resuming the canvas,
/// quitting with every window back on a screen.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let mode: Mode
    private(set) var controller: Controller?
    private var statusItem: NSStatusItem?
    private var watcher: Process?
    private var stopping = false // a shutdown is unparking windows
    private var quitWhenStopped = false
    private var signals: [DispatchSourceSignal] = []
    private var aeroSpaceToken: NSObjectProtocol? // set while waiting for AeroSpace to quit
    private var waitingForAeroSpace: Bool { aeroSpaceToken != nil }
    private var onboarding: Onboarding?
    private var onboardingDone = false // Continue without Screen Recording: don't ask again this run
    private var settingsWindow: SettingsWindow?
    private var importNote: String? // a first-launch AeroSpace import, told once

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

    // MARK: Canvas on and off

    private func startCanvas() {
        guard controller == nil, !stopping else { return }
        let c = Controller(mode: mode)
        c.onChange = { [weak self] in self?.refreshIcon() }
        c.onWorkspaces = { [weak self] _ in self?.refreshIcon() }
        c.onSettings = { [weak self] pane in self?.showSettings(at: pane) }
        c.bindingsSuspended = settingsWindow?.model.recording != nil
        controller = c
        c.start()
        if mode == .normal { startWatcher() }
        refreshIcon()
    }

    private func stopCanvas() {
        guard let c = controller else { return }
        controller = nil
        stopping = true
        c.shutdown { [weak self] in
            guard let self else { return }
            stopping = false
            stopWatcher()
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

    // MARK: Menu

    /// The workspace numbers (the setting, while the canvas runs), else the
    /// icon; a warning sign while the config has problems.
    private func refreshIcon() {
        guard let button = statusItem?.button else { return }
        let settings = currentSettings
        let status = controller?.workspaceStatus
        if !configErrors.isEmpty {
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "mielwm: the config has problems")
        } else if let status, settings.menuBarWorkspaces, !status.numbers.isEmpty {
            button.image = workspaceIndicator(status.numbers, current: status.current)
            button.image?.accessibilityDescription = "mielwm: " + (status.current.map { "workspace \($0)" } ?? "workspaces")
        } else {
            button.image = menuBarIconImage
        }
        button.image?.isTemplate = true
        button.appearsDisabled = controller == nil // paused, or waiting for permissions or AeroSpace
    }

    // Every item has a symbol: macOS 26 adds one to Settings… on its own, and the titles should line up.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        @discardableResult
        func add(_ title: String, _ symbol: String, _ action: Selector?, key: String = "", enabled: Bool = true) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            item.isEnabled = enabled && action != nil
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(item)
            return item
        }
        let on = controller != nil
        add(statusLine.title, statusLine.symbol, nil, enabled: false)
        if waitingForAeroSpace {
            add(swipeAeroSpace() == nil ? "Quit AeroSpace" : "Quit AeroSpace and SwipeAeroSpace", "xmark.circle", #selector(quitAeroSpace))
        }
        let overview = add("Overview", "square.grid.2x2", #selector(overview), enabled: on)
        if let chord = currentSettings.chords(for: .toggleOverview).first, let key = menuKey(chord) {
            overview.keyEquivalent = key.0
            overview.keyEquivalentModifierMask = key.1
        }
        add("Tidy windows", "rectangle.3.group", #selector(tidy), enabled: on)
        menu.addItem(.separator())
        let paused = !on && !stopping
        add(paused ? "Resume mielwm" : "Pause mielwm", paused ? "play.circle" : "pause.circle", #selector(toggleCanvas),
            enabled: !waitingForAeroSpace && onboarding == nil && !stopping)
        menu.addItem(.separator())
        if !configErrors.isEmpty { add("Config has problems…", "exclamationmark.triangle", #selector(showConfigProblems)) }
        add("Settings…", "gearshape", #selector(openSettings), key: ",")
        add("About mielwm", "info.circle", #selector(about))
        menu.addItem(.separator())
        add("Quit mielwm", "power", #selector(quit), key: "q")
    }

    /// The first, disabled line of the menu: what mielwm is doing.
    private var statusLine: (title: String, symbol: String) {
        if onboarding != nil { return ("Waiting for permissions", "lock") }
        if waitingForAeroSpace { return ("Waiting for AeroSpace to quit", "hourglass") }
        guard let status = controller?.workspaceStatus else { return (stopping ? "Pausing…" : "Paused", "pause") }
        guard let n = status.current else { return ("On the canvas", "square.dashed") }
        return ("Workspace \(n)" + (status.mode.map { $0 == .stack ? " · Stack" : " · Tiles" } ?? ""), "\(n).square")
    }

    private var currentSettings: MielCore.Settings { controller?.state.settings ?? loadSettings(.standard()).settings }
    private var configErrors: [String] { controller?.configErrors ?? loadSettings(.standard()).errors }

    @objc private func toggleCanvas() { controller == nil ? begin() : stopCanvas() }
    @objc private func overview() { controller?.input(.action(.toggleOverview)) }
    @objc private func tidy() { controller?.input(.action(.arrange)) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openSettings() { showSettings(at: nil) }

    /// The Settings window, at `pane` or where it was left.
    func showSettings(at pane: SettingsPane?) {
        if settingsWindow == nil {
            let model = SettingsModel()
            model.onWrite = { [weak self] in self?.controller?.reloadConfig() }
            model.onLive = { [weak self] in self?.controller?.applyLive($0) }
            model.onRecording = { [weak self] on in self?.controller?.bindingsSuspended = on }
            settingsWindow = SettingsWindow(model: model)
        }
        settingsWindow?.show(pane)
    }

    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: aboutOptions)
    }

    @objc private func showConfigProblems() {
        let alert = Self.configProblemsAlert(configErrors)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { openConfigFile(ConfigPaths.standard().config) }
    }

    static func configProblemsAlert(_ errors: [String]) -> NSAlert {
        let alert = NSAlert.mielwm()
        alert.alertStyle = .warning
        alert.messageText = "Some settings could not be read"
        alert.informativeText = errors.joined(separator: "\n") + "\n\nmielwm uses the defaults for those until the file is fixed."
        alert.addButton(withTitle: "Open config file")
        alert.addButton(withTitle: "OK")
        return alert
    }

    @objc private func quitAeroSpace() {
        swipeAeroSpace()?.terminate()
        AeroSpace.terminate()
    }

    /// The chord as a menu key equivalent, so the menu shows it with the system's glyphs.
    private func menuKey(_ chord: KeyChord) -> (String, NSEvent.ModifierFlags)? {
        var mask: NSEvent.ModifierFlags = []
        if chord.modifiers.contains(.control) { mask.insert(.control) }
        if chord.modifiers.contains(.option) { mask.insert(.option) }
        if chord.modifiers.contains(.shift) { mask.insert(.shift) }
        if chord.modifiers.contains(.command) { mask.insert(.command) }
        let special: [String: Int] = ["left": NSLeftArrowFunctionKey, "right": NSRightArrowFunctionKey, "up": NSUpArrowFunctionKey,
                                      "down": NSDownArrowFunctionKey, "tab": 0x09, "return": 0x0D, "escape": 0x1B, "delete": 0x08,
                                      "space": 0x20, "home": NSHomeFunctionKey, "end": NSEndFunctionKey,
                                      "pageup": NSPageUpFunctionKey, "pagedown": NSPageDownFunctionKey, "forwarddelete": NSDeleteFunctionKey]
        let punctuation = ["minus": "-", "equal": "=", "comma": ",", "period": ".", "slash": "/", "semicolon": ";", "quote": "'",
                           "grave": "`", "backslash": "\\", "leftbracket": "[", "rightbracket": "]"]
        if let code = special[chord.key] ?? (chord.key.hasPrefix("f") && chord.key.count > 1 ? Int(chord.key.dropFirst()).map { NSF1FunctionKey + $0 - 1 } : nil) {
            return (String(Character(UnicodeScalar(code)!)), mask)
        }
        return (punctuation[chord.key] ?? chord.key, mask)
    }

    // MARK: AeroSpace and Spaces

    /// AeroSpace would fight every move. Declined: manage nothing until it quits.
    private func askAboutAeroSpace() {
        let alert = Self.aeroSpaceAlert(swipe: swipeAeroSpace() != nil, note: takeImportNote())
        NSApp.activate(ignoringOtherApps: true)
        let quit = alert.runModal() == .alertFirstButtonReturn
        aeroSpaceToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, AeroSpace.running() == nil else { return }
                self.aeroSpaceToken.map(NSWorkspace.shared.notificationCenter.removeObserver)
                self.aeroSpaceToken = nil
                self.begin()
            }
        }
        refreshIcon()
        if quit { quitAeroSpace() }
    }

    /// Quit AeroSpace (and SwipeAeroSpace), the default on the right, or wait.
    static func aeroSpaceAlert(swipe: Bool, note: String?) -> NSAlert {
        let alert = NSAlert.mielwm()
        alert.messageText = swipe ? "Quit AeroSpace and SwipeAeroSpace?" : "Quit AeroSpace?"
        var text = """
            mielwm and AeroSpace would both move your windows, so mielwm waits until AeroSpace quits. \
            To keep AeroSpace from opening at login, set start-at-login = false in its config.
            """
        if swipe {
            text += """
                \n\nSwipeAeroSpace drives AeroSpace, and it once froze all input when mielwm's permissions \
                changed, so it's safest to quit both.
                """
        }
        if let note { text += "\n\n" + note }
        alert.informativeText = text
        alert.addButton(withTitle: swipe ? "Quit both" : "Quit AeroSpace")
        alert.addButton(withTitle: "Not now")
        return alert
    }

    /// SwipeAeroSpace drives AeroSpace with trackpad swipes.
    private func swipeAeroSpace() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.localizedName == "SwipeAeroSpace" || ($0.bundleIdentifier ?? "").localizedCaseInsensitiveContains("swipeaerospace")
        }
    }

    /// First launch (no config.json yet) beside an AeroSpace config: takes its
    /// gaps, layout and rules. Not its keys: the defaults already are AeroSpace's.
    private func importAeroSpaceOnFirstLaunch() -> String? {
        let paths = ConfigPaths.standard()
        guard !FileManager.default.fileExists(atPath: paths.config.path), let url = AeroSpaceImport.standardURL(),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var found = AeroSpaceImport(toml: text)
        found.bindings = [:]
        let changes = found.changes(onto: MielCore.Settings(), keys: false)
        guard changes.values.contains(where: { $0 != nil }) else { return nil }
        do { try updateConfig(changes, paths: paths) } catch {
            log("AeroSpace import: \(error)")
            return nil
        }
        return aeroSpaceImportNote(found)
    }

    private func takeImportNote() -> String? {
        defer { importNote = nil }
        return importNote
    }

    private func showImportNotice(_ note: String) {
        let alert = NSAlert.mielwm()
        alert.messageText = "Settings imported from AeroSpace"
        alert.informativeText = note
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Settings")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { showSettings(at: .layout) }
    }

    /// Windows can't sit across two displays while each display has its own Spaces. Told once.
    private func noticeSeparateSpaces() {
        let key = "separateSpacesNoticeShown"
        guard NSScreen.screens.count > 1, !Displays.spansDisplays(), !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let alert = NSAlert.mielwm()
        alert.messageText = "Turn off “Displays have separate Spaces”"
        alert.informativeText = """
            While it's on, macOS keeps each window on one display, so a window can't sit across two \
            displays and dragging between them snaps. Turn it off in System Settings > Desktop & Dock > \
            Mission Control, then log out and back in.
            """
        alert.addButton(withTitle: "Open Desktop & Dock")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
        }
    }

    // MARK: Permissions

    private func showOnboarding() {
        guard onboarding == nil else { return }
        onboarding = Onboarding(note: takeImportNote()) { [weak self] in
            self?.onboarding = nil
            self?.onboardingDone = true
            self?.begin()
        }
        refreshIcon()
    }
}

extension AppDelegate {
    /// The status menu as it is with `controller` (not started), for --settings-preview.
    func previewMenu(_ controller: Controller?) -> NSMenu {
        self.controller = controller
        let menu = NSMenu()
        menuNeedsUpdate(menu)
        return menu
    }
}

// MARK: - Menu bar images, the app icon and About

/// The workspace numbers as a template image: the current one knocked out
/// of a filled rounded square, the others plain. Drawn at any scale.
func workspaceIndicator(_ numbers: [Int], current: Int?) -> NSImage {
    let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    let cell = NSSize(width: 15, height: 15), gap: CGFloat = 2
    let size = NSSize(width: CGFloat(numbers.count) * (cell.width + gap) - gap, height: cell.height)
    let image = NSImage(size: size, flipped: false) { _ in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        for (i, n) in numbers.enumerated() {
            let box = CGRect(x: CGFloat(i) * (cell.width + gap), y: 0, width: cell.width, height: cell.height)
            let text = "\(n)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            let width = text.size(withAttributes: attributes).width
            // Digits sit on the baseline and rise to the cap height: center that.
            let origin = CGPoint(x: box.midX - width / 2, y: ((box.midY - font.capHeight / 2) * 2).rounded() / 2 + font.descender)
            if n == current {
                NSColor.black.setFill()
                NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
                ctx.setBlendMode(.destinationOut)
                text.draw(at: origin, withAttributes: attributes)
                ctx.setBlendMode(.normal)
            } else {
                text.draw(at: origin, withAttributes: attributes)
            }
        }
        return true
    }
    image.isTemplate = true
    return image
}

/// A file from the app's resources: the bundle's, or Resources/ in the checkout, for a development build.
func resourceURL(_ name: String, extensions: [String]) -> URL? {
    for ext in extensions {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
    }
    var dir = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
    for _ in 0 ..< 6 { // .build/<triple>/debug up to the checkout
        guard let d = dir else { break }
        for ext in extensions {
            let url = d.appendingPathComponent("Resources/\(name).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        dir = d.deletingLastPathComponent()
    }
    return nil
}

/// The menu bar glyph: the template in Resources (MenuBarIcon.pdf, or .png
/// with an @2x beside it), else an SF Symbol.
let menuBarIconImage: NSImage? = {
    guard let url = resourceURL("MenuBarIcon", extensions: ["pdf", "png"]), let image = NSImage(contentsOf: url) else {
        return NSImage(systemSymbolName: "rectangle.on.rectangle.dashed", accessibilityDescription: "mielwm")
    }
    if let retina = NSImageRep(contentsOf: url.deletingLastPathComponent().appendingPathComponent("MenuBarIcon@2x.png")), url.pathExtension == "png" {
        retina.size = image.size
        image.addRepresentation(retina)
    }
    let height: CGFloat = 18
    image.size = NSSize(width: (image.size.width * height / max(image.size.height, 1)).rounded(), height: height)
    image.isTemplate = true
    image.accessibilityDescription = "mielwm"
    return image
}()

extension NSAlert {
    /// An alert with the app icon (an unbundled build would show a folder).
    static func mielwm() -> NSAlert {
        let alert = NSAlert()
        alert.icon = appIcon()
        return alert
    }
}

/// The app icon: the bundle's, or Resources/AppIcon.icns beside a
/// development build, else the menu bar glyph on an icon-shaped tile.
func appIcon() -> NSImage {
    if Bundle.main.bundleURL.pathExtension == "app" { return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath) }
    if let url = resourceURL("AppIcon", extensions: ["icns"]), let image = NSImage(contentsOf: url) { return image }
    return NSImage(size: NSSize(width: 128, height: 128), flipped: false) { rect in
        let tile = rect.insetBy(dx: 12.5, dy: 12.5) // the margin and corner of macOS icons
        let path = NSBezierPath(roundedRect: tile, xRadius: 23, yRadius: 23)
        NSGradient(starting: NSColor(srgbRed: 0.36, green: 0.36, blue: 0.4, alpha: 1), ending: NSColor(srgbRed: 0.16, green: 0.16, blue: 0.19, alpha: 1))?
            .draw(in: path, angle: -90)
        let symbol = NSImage(systemSymbolName: "rectangle.on.rectangle.dashed", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 52, weight: .regular).applying(.init(paletteColors: [.white])))
        if let symbol {
            symbol.draw(in: NSRect(x: rect.midX - symbol.size.width / 2, y: rect.midY - symbol.size.height / 2, width: symbol.size.width, height: symbol.size.height))
        }
        return true
    }
}

@MainActor
var aboutOptions: [NSApplication.AboutPanelOptionKey: Any] {
    [
        .applicationName: "mielwm",
        .applicationVersion: appVersion,
        .version: "",
        .applicationIcon: appIcon(),
        .credits: NSAttributedString(string: "Every window on one endless canvas.", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: { let p = NSMutableParagraphStyle(); p.alignment = .center; return p }(),
        ]),
    ]
}
