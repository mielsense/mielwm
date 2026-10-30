import AppKit
import MielCore
import MielSystem

extension AppDelegate {
    /// AeroSpace would fight every move. Declined: manage nothing until it quits.
    func askAboutAeroSpace() {
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
    func swipeAeroSpace() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.localizedName == "SwipeAeroSpace" || ($0.bundleIdentifier ?? "").localizedCaseInsensitiveContains("swipeaerospace")
        }
    }

    /// First launch (no config.json yet) beside an AeroSpace config: takes its
    /// gaps, layout and rules. Not its keys: the defaults already are AeroSpace's.
    func importAeroSpaceOnFirstLaunch() -> String? {
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

    func takeImportNote() -> String? {
        defer { importNote = nil }
        return importNote
    }

    func showImportNotice(_ note: String) {
        let alert = NSAlert.mielwm()
        alert.messageText = "Settings imported from AeroSpace"
        alert.informativeText = note
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Settings")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { showSettings(at: .layout) }
    }

    /// Windows can't sit across two displays while each display has its own Spaces. Told once.
    func noticeSeparateSpaces() {
        let key = "separateSpacesNoticeShown"
        guard NSScreen.screens.count > 1, !Displays.spansDisplays(), !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let alert = NSAlert.mielwm()
        alert.messageText = "Turn off \"Displays have separate Spaces\""
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
}
