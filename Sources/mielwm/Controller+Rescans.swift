import AppKit
import MielCore
import MielSystem

extension Controller {
    static let rescanInterval = 5.0 // seconds between rereads of every window list

    /// Rereads the window lists now and then, for notifications macOS dropped.
    func startRescans() {
        let timer = Timer.scheduledTimer(withTimeInterval: Self.rescanInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.registry.rescan() }
        }
        timer.tolerance = 1 // lets macOS wake us together with other timers
        rescanTimer = timer
    }
}
