import AppKit
import MielCore
import MielSystem

extension AppDelegate {
    /// The workspace numbers (the setting, while the canvas runs), else the
    /// icon; a warning sign while the config has problems.
    func refreshIcon() {
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
            model.onBarik = { [weak self, weak model] on in if let model { self?.setBarik(on, model) } }
            model.barikAvailable = barik != nil
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

    @objc func quitAeroSpace() {
        swipeAeroSpace()?.terminate()
        AeroSpace.terminate()
    }

    /// The chord as a menu key equivalent, so the menu shows it with the system's glyphs.
    private func menuKey(_ chord: KeyChord) -> (String, NSEvent.ModifierFlags)? {
        let mask = NSEvent.ModifierFlags(chord.modifiers)
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

    /// The status menu as it is with `controller` (not started), for --settings-preview.
    func previewMenu(_ controller: Controller?) -> NSMenu {
        self.controller = controller
        let menu = NSMenu()
        menuNeedsUpdate(menu)
        return menu
    }
}
