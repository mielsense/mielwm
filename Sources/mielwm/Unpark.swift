import Foundation
import MielCore
import MielSystem

/// Every window the saved layout has parked (or left off screen), back on a screen.
@MainActor
func unparkFromLayout() -> Bool {
    guard let layout = LayoutSnapshot.load(from: LayoutSnapshot.standardURL()) else {
        print("mielwm: no saved layout, nothing to unpark")
        return true
    }
    let commands = unparkCommands(layout, screens: Displays.screens())
    guard !commands.isEmpty else {
        print("mielwm: no parked windows")
        return true
    }
    let registry = WindowRegistry { _ in }
    registry.start()
    let ok = registry.performAndWait(commands, timeout: 3)
    print("mielwm: unparked \(counted(commands.count, "window"))\(ok ? "" : " (some apps did not answer)")")
    return ok
}

/// The crash watcher: when `pid` exits without stopping us first (a clean
/// quit does), unpark from layout.json.
@MainActor
func watch(_ pid: Int32) -> Never {
    signal(SIGINT, SIG_IGN) // a terminal's Ctrl-C reaches the app, which unparks itself
    signal(SIGHUP, SIG_IGN)
    let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
    source.setEventHandler {
        MainActor.assumeIsolated {
            log("the app (pid \(pid)) died; unparking")
            exit(unparkFromLayout() ? 0 : 1)
        }
    }
    source.resume()
    if kill(pid, 0) != 0 { exit(unparkFromLayout() ? 0 : 1) }
    RunLoop.main.run()
    exit(0)
}
