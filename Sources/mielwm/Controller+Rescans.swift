import AppKit
import MielCore
import MielSystem

extension Controller {
    static let rescanInterval = 10.0 // seconds between rereads of every window list

    /// Rereads the window lists now and then, for notifications macOS dropped,
    /// and after waking, when macOS has moved windows while displays went and came.
    /// Nothing is read while the displays sleep or another user has the screen.
    func startRescans() {
        let center = NSWorkspace.shared.notificationCenter
        func on(_ name: Notification.Name, _ act: @escaping @MainActor (Controller) -> Void) {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { act(self) } }
            })
        }
        // Not on going to sleep: a grace period started then runs out during
        // sleep, and the overdue tick would put windows back before displays return.
        on(NSWorkspace.didWakeNotification) { $0.registry.woke() }
        on(NSWorkspace.screensDidWakeNotification) { $0.pauseRescans("displays", false); $0.registry.woke() }
        on(NSWorkspace.screensDidSleepNotification) { $0.pauseRescans("displays", true) }
        on(NSWorkspace.sessionDidResignActiveNotification) { $0.pauseRescans("session", true) }
        on(NSWorkspace.sessionDidBecomeActiveNotification) { $0.pauseRescans("session", false); $0.registry.rescan() }
        pauseRescans("", false) // starts the timer
    }

    /// The timer runs while nothing pauses it.
    private func pauseRescans(_ reason: String, _ paused: Bool) {
        if paused { rescanPauses.insert(reason) } else { rescanPauses.remove(reason) }
        if !rescanPauses.isEmpty {
            rescanTimer?.invalidate()
            rescanTimer = nil
        } else if rescanTimer == nil {
            let timer = Timer.scheduledTimer(withTimeInterval: Self.rescanInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.registry.rescan() }
            }
            timer.tolerance = 2 // lets macOS wake us together with other timers
            rescanTimer = timer
        }
    }
}
