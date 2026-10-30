import AppKit
import MielCore
import MielSystem

extension Controller {
    static let rescanInterval = 5.0 // seconds between rereads of every window list

    /// Rereads the window lists now and then, for notifications macOS dropped,
    /// and after waking, when macOS has moved windows while displays went and came.
    func startRescans() {
        let timer = Timer.scheduledTimer(withTimeInterval: Self.rescanInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.registry.rescan() }
        }
        timer.tolerance = 1 // lets macOS wake us together with other timers
        rescanTimer = timer
        let center = NSWorkspace.shared.notificationCenter
        // Not on going to sleep: a grace period started then runs out during
        // sleep, and the overdue tick would put windows back before displays return.
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.woke() }
            })
        }
    }

    /// Like a screen change: Core ignores frame reports for a moment, then puts
    /// every window back in its spot. The app list does not change across sleep.
    private func woke() {
        system(.screensChanged(Displays.screens()))
        registry.rescan()
    }
}
