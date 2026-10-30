import AppKit
import Carbon.HIToolbox
import MielCore
import MielSystem

extension AppDelegate {
    /// The workspace numbers as menubar:style asks (while the canvas runs),
    /// else the icon; a warning sign while the config has problems.
    func refreshIcon() {
        guard let button = statusItem?.button else { return }
        let settings = currentSettings
        let status = controller?.workspaceStatus
        if !configErrors.isEmpty {
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "mielwm: the config has problems")
        } else if let status, let numbers = Self.shownNumbers(settings.menuBarStyle, status), !numbers.isEmpty {
            button.image = workspaceIndicator(numbers, current: status.current)
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
        // Keys reach the shortcuts through an event tap, and secure input hides them from it.
        if on, IsSecureEventInputEnabled() {
            add("Secure input is on, shortcuts may not work", "lock.shield", nil, enabled: false).toolTip =
                "An app turned on secure input, often for a password field or Terminal's Secure Keyboard Entry."
        }
        let workspaces = menuWorkspaces
        if !workspaces.isEmpty {
            menu.addItem(.separator())
            let current = controller?.workspaceStatus.current
            for (n, apps) in workspaces {
                let item = add("Workspace \(n)", "\(n).square", #selector(goToWorkspace), enabled: on)
                item.tag = n
                item.state = n == current ? .on : .off
                item.attributedTitle = Self.workspaceTitle(item.title, icons: apps.prefix(4).compactMap(\.icon))
                item.toolTip = apps.compactMap(\.localizedName).joined(separator: ", ")
            }
            menu.addItem(.separator())
        }
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

    /// The numbers the menu bar shows in `style`; nil for the icon.
    static func shownNumbers(_ style: MenuBarStyle, _ status: Controller.WorkspaceStatus) -> [Int]? {
        switch style {
        case .all: status.numbers
        case .current: status.current.map { [$0] }
        case .icon: nil
        }
    }

    /// The workspaces the menu bar numbers, those with windows, with their apps in tile order.
    private var menuWorkspaces: [(number: Int, apps: [NSRunningApplication])] {
        guard let controller else { return [] }
        return controller.workspaceStatus.numbers.compactMap { n in
            guard let ws = controller.state.workspaces.first(where: { $0.number == n }), !ws.members.isEmpty else { return nil }
            var pids: [pid_t] = []
            for id in ws.members where !pids.contains(id.pid) { pids.append(id.pid) }
            return (n, pids.compactMap { NSRunningApplication(processIdentifier: $0) })
        }
    }

    /// The title, then small app icons after it.
    private static func workspaceTitle(_ title: String, icons: [NSImage]) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let text = NSMutableAttributedString(string: title + "  ", attributes: [.font: font])
        for icon in icons {
            let attachment = NSTextAttachment()
            attachment.image = icon
            attachment.bounds = CGRect(x: 0, y: ((font.capHeight - 16) / 2).rounded(), width: 16, height: 16)
            text.append(NSAttributedString(attachment: attachment))
            text.append(NSAttributedString(string: " ", attributes: [.font: font]))
        }
        return text
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
    @objc private func goToWorkspace(_ item: NSMenuItem) { controller?.input(.action(.workspace(item.tag))) }
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
            model.readScreens = { [weak self] in self?.controller?.state.screens ?? Displays.screens() }
            settingsWindow = SettingsWindow(model: model)
        }
        settingsWindow?.show(pane)
    }

    @objc private func about() {
        showSettings(at: .about) // one About, the Settings pane
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
