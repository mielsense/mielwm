import AppKit

// mielwm-testwindows: opens throwaway windows for system tests, so tests
// never touch real ones.
//
//   mielwm-testwindows [--count N] [--frames "x,y,w,h;x,y,w,h"] [--still] [--hidden] [--untitled]
//
// They repaint 60 times a second (like a video), unless --still. --hidden
// hides the app once it runs. --untitled opens PT-1 without a title bar, so
// it is not a standard window until SIGUSR2 gives it one. SIGINFO orders PT-1
// out: hidden, not closed, as apps that close to the menu bar do.
//
// Frames are global points, y-down from the primary display's top-left, like
// everything in mielwm. Windows are titled PT-1 ... PT-N. Prints its pid,
// then stays until killed. SIGUSR1 moves PT-1 right 100 and down 60 points,
// as an app moving its own window would. An accessory app, so window managers that only
// manage regular apps (AeroSpace) leave its windows alone.

/// Repaints with a moving hue, so window captures always have new frames.
final class PulseView: NSView {
    private var hue = 0.0

    override func draw(_ dirtyRect: NSRect) {
        NSColor(hue: hue, saturation: 0.5, brightness: 0.9, alpha: 1).setFill()
        bounds.fill()
    }

    func tick() {
        hue = (hue + 0.005).truncatingRemainder(dividingBy: 1)
        needsDisplay = true
    }
}

func argument(_ flag: String) -> String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let frames: [CGRect] = (argument("--frames") ?? "").split(separator: ";").compactMap { item in
    let n = item.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    return n.count == 4 ? CGRect(x: n[0], y: n[1], width: n[2], height: n[3]) : nil
}
let count = Int(argument("--count") ?? "") ?? max(frames.count, 1)

let standardStyle: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
var views: [PulseView] = []
var windows: [NSWindow] = []
for i in 0..<count {
    let f = i < frames.count ? frames[i] : CGRect(x: 120 + 40 * i, y: 120 + 40 * i, width: 480, height: 320)
    let untitled = i == 0 && CommandLine.arguments.contains("--untitled")
    let window = NSWindow(contentRect: .zero, styleMask: untitled ? [.borderless] : standardStyle,
                          backing: .buffered, defer: false)
    window.title = "PT-\(i + 1)"
    window.isReleasedWhenClosed = false
    let view = PulseView()
    window.contentView = view
    window.setFrame(CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height), display: true)
    window.orderFrontRegardless()
    views.append(view)
    windows.append(window)
}
if !CommandLine.arguments.contains("--still") {
    Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in MainActor.assumeIsolated { views.forEach { $0.tick() } } }
}
signal(SIGUSR1, SIG_IGN)
let moveSignal = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
moveSignal.setEventHandler {
    guard let w = windows.first else { return }
    w.setFrameOrigin(NSPoint(x: w.frame.minX + 100, y: w.frame.minY - 60)) // AppKit's y grows upward
}
moveSignal.resume()
signal(SIGUSR2, SIG_IGN)
let styleSignal = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
styleSignal.setEventHandler { windows.first?.styleMask = standardStyle }
styleSignal.resume()
signal(SIGINFO, SIG_IGN)
let orderOutSignal = DispatchSource.makeSignalSource(signal: SIGINFO, queue: .main)
orderOutSignal.setEventHandler { windows.first?.orderOut(nil) }
orderOutSignal.resume()
if CommandLine.arguments.contains("--hidden") { DispatchQueue.main.async { app.hide(nil) } }

print(ProcessInfo.processInfo.processIdentifier)
fflush(stdout)
app.run()
