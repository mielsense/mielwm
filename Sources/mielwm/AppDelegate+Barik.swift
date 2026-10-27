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
        if on, barik.config == nil {
            _ = Self.barikNoConfigAlert().runModal()
            return
        }
        guard Self.barikAlert(on: on, config: barik.config).runModal() == .alertFirstButtonReturn else { return }
        do {
            try on ? barik.turnOn() : barik.turnOff()
            model.apply(["integrations:barik": Settings.entry("integrations:barik", .flag(on))])
        } catch {
            model.problem = "Barik: \(Self.describe(error))"
        }
    }

    static func barikAlert(on: Bool, config: URL?) -> NSAlert {
        let alert = NSAlert.mielwm()
        let file = config.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "Barik's config"
        if on {
            alert.messageText = "Work with Barik?"
            alert.informativeText = """
                mielwm will set aerospace.path in \(file) to its own aerospace command, after saving a copy \
                next to it. Then it starts a hidden helper called AeroSpace and relaunches Barik, so Barik \
                shows mielwm's workspaces.
                """
            alert.addButton(withTitle: "Turn On")
        } else {
            alert.messageText = "Stop working with Barik?"
            alert.informativeText = """
                mielwm will put Barik's old aerospace.path back in \(file), quit its AeroSpace helper and \
                relaunch Barik.
                """
            alert.addButton(withTitle: "Turn Off")
        }
        alert.addButton(withTitle: "Cancel")
        return alert
    }

    static func barikNoConfigAlert() -> NSAlert {
        let alert = NSAlert.mielwm()
        alert.messageText = "Open Barik once first"
        alert.informativeText = "Barik makes its config the first time it runs, and mielwm needs it. Open Barik, then turn this on again."
        alert.addButton(withTitle: "OK")
        return alert
    }

    static func barikMoveFirstAlert() -> NSAlert {
        let alert = NSAlert.mielwm()
        alert.messageText = "Move mielwm to Applications first"
        alert.informativeText = """
            mielwm is running from a disk image or a temporary place macOS made for it, which goes away when \
            it quits, and Barik would lose it. Move mielwm to Applications, open it from there, then turn this on.
            """
        alert.addButton(withTitle: "OK")
        return alert
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case let BarikLink.Problem.unsupported(path): "\(path) sets aerospace in a way mielwm can't edit. Set aerospace.path by hand."
        default: error.localizedDescription
        }
    }
}
