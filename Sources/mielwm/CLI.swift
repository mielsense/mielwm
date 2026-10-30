import AppKit
import MielCore
import MielIPC
import MielSystem

// The command-line tools. None of them moves a window except --unpark and
// --watch, which only put parked windows back on a screen.

/// The word after `flag` in `args`.
func value(_ flag: String, in args: [String]) -> String? {
    args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(2)
}

/// Runs the main run loop until `done` or `seconds` pass (AX events and
/// ScreenCaptureKit completions arrive on the main queue).
@MainActor
func spin(_ seconds: Double, until done: () -> Bool = { false }) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end, !done() { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
}

/// Every window Accessibility reports, after a moment to settle. Read only.
@MainActor
func readWindows(pid: Int32? = nil) -> (windows: [WindowSnapshot], focused: WindowID?) {
    var focused: WindowID?
    let registry = WindowRegistry(pidFilter: pid) { event in if case let .windowFocused(id) = event { focused = id } }
    registry.start()
    var count = -1, stableSince = Date()
    spin(6) {
        if registry.windows.count != count { count = registry.windows.count; stableSince = Date() }
        return count > 0 && Date().timeIntervalSince(stableSince) > 1
    }
    let windows = Array(registry.windows.values).sorted { ($0.appName, $0.title, $0.id.number) < ($1.appName, $1.title, $1.id.number) }
    registry.stop()
    return (windows, focused)
}


/// Sends a command to the running app and prints its answer.
func send(_ args: [String]) -> Int32 {
    let text = args.joined(separator: " ")
    guard ["state", "quit"].contains(text) || Action(command: text) != nil else {
        fail("mielwm: unknown action '\(text)' (see mielwm --help)")
    }
    do {
        let data = try IPCClient.send(args)
        print(String(decoding: data, as: UTF8.self))
        return data.starts(with: Data(#"{"error""#.utf8)) ? 1 : 0
    } catch IPCError.notRunning {
        fail("mielwm is not running (open mielwm.app first; mielwm --help lists the commands)")
    } catch {
        fail("mielwm: \(error)")
    }
}

/// The screen region "x,y,width,height" (points from the primary display's top-left) as a PNG.
func screencapture(_ region: String, to url: URL) {
    let shot = Process()
    shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    shot.arguments = ["-x", "-R", region, url.path]
    try? shot.run()
    shot.waitUntilExit()
}

/// Runs AppKit's event loop for `seconds`, as NSApp.run would: windows
/// lay out and redraw, monitors see events.
@MainActor
func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        if let event = NSApp.nextEvent(matching: .any, until: min(end, Date().addingTimeInterval(0.02)), inMode: .default, dequeue: true) {
            NSApp.sendEvent(event)
        }
        NSApp.updateWindows()
    }
}
