import AppKit
import MielCore
import MielSystem

extension AppDelegate {
    /// Barik's link, in mielwm.app only: the `aerospace` command and the helper live in the bundle.
    static func makeBarikLink() -> BarikLink? {
        let helpers = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers")
        let shim = helpers.appendingPathComponent("aerospace"), helper = helpers.appendingPathComponent("AeroSpace.app")
        guard FileManager.default.isExecutableFile(atPath: shim.path), FileManager.default.fileExists(atPath: helper.path) else { return nil }
        return BarikLink(shim: shim.path, helper: helper, apps: SystemBarikApps())
    }

    /// The Settings switch: asks first, then turns the link on or off and saves the switch.
    func setBarik(_ on: Bool, _ model: SettingsModel) {
        guard let barik else { return }
        NSApp.activate(ignoringOtherApps: true)
        if on, barik.temporaryLocation {
            _ = Self.barikMoveFirstAlert().runModal()
            return
        }
        guard Self.barikAlert(on: on, config: barik.config, icon: on && model.settings.menuBarStyle == .all).runModal() == .alertFirstButtonReturn else { return }
        do {
            try on ? barik.turnOn() : barik.turnOff()
            var changes = ["integrations:barik": Settings.entry("integrations:barik", .flag(on))]
            if on, model.settings.menuBarStyle == .all { // Barik shows the numbers; the icon keeps them from showing twice
                changes.merge(MenuBarStyle.icon.configChanges) { $1 }
            }
            model.apply(changes)
        } catch {
            model.problem = "Work with AeroSpace-compatible apps: \(Self.describe(error))"
        }
    }

    /// `config`: Barik's config, which mielwm edits when there is one.
    /// `icon`: turning on also sets mielwm's menu bar item to its icon.
    static func barikAlert(on: Bool, config: URL?, icon: Bool = false) -> NSAlert {
        let alert = NSAlert.mielwm()
        let file = config.map { ($0.path as NSString).abbreviatingWithTildeInPath }
        if on {
            alert.messageText = "Work with AeroSpace-compatible apps?"
            alert.informativeText = "mielwm will start a hidden helper called AeroSpace, so menu bars and tools made for AeroSpace "
                + "show mielwm's workspaces through its aerospace command."
                + (file.map { " It sets aerospace.path in \($0) to that command, after saving a copy next to it, and relaunches the app that reads it." } ?? "")
                + (icon ? " mielwm's own menu bar item changes to its icon, so the workspaces don't show twice." : "")
            alert.addButton(withTitle: "Turn on")
        } else {
            alert.messageText = "Stop working with AeroSpace-compatible apps?"
            alert.informativeText = file.map {
                "mielwm will put the old aerospace.path back in \($0), quit its AeroSpace helper and relaunch the app that reads it."
            } ?? "mielwm will quit its AeroSpace helper."
            alert.addButton(withTitle: "Turn off")
        }
        alert.addButton(withTitle: "Cancel")
        return alert
    }

    static func barikMoveFirstAlert() -> NSAlert {
        let alert = NSAlert.mielwm()
        alert.messageText = "Move mielwm to Applications first"
        alert.informativeText = """
            mielwm is running from a disk image or a temporary folder macOS made for it, which goes away when \
            it quits, and apps using its aerospace command would lose it. Move mielwm to Applications, open it from there, then turn this on.
            """
        alert.addButton(withTitle: "OK")
        return alert
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case let BarikLink.Problem.unsupported(path): "\(path) sets aerospace in a way mielwm can't edit. Set aerospace.path by hand."
        case BarikLink.Problem.temporaryLocation: "Move mielwm to Applications, open it from there, then turn this on."
        default: error.localizedDescription
        }
    }
}
