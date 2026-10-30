import AppKit
import MielCore
import MielRender
import MielSystem

/// `--overview-preview`: the overview's native chrome over a rendered canvas
/// of synthetic windows, for each state, glass style and appearance, saved as
/// PNGs of the main display. It covers the screen for a moment (glass only
/// renders on screen); nothing moves and no input is read. The capture needs
/// Screen Recording for the terminal.
@MainActor
func overviewPreview(_ args: [String]) -> Never {
    NSApplication.shared.setActivationPolicy(.accessory)
    let out = URL(fileURLWithPath: value("--out", in: args) ?? "overview-preview", isDirectory: true)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    guard let screen = Displays.screens().first, let ns = NSScreen.screens.first, let renderer = try? Renderer() else { fail("no display or Metal") }
    var wallpaper: CGImage?, loaded = false
    MielSystem.Wallpaper.image(for: screen) { wallpaper = $0; loaded = true }
    spin(5) { loaded }
    renderer.setWallpaper(wallpaper, screenID: screen.id)

    // The overlay as the app makes it: the canvas, the chrome above it. A second window
    // behind stands in for the desktop the ⌥Tab switcher shows over.
    let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
    func window(_ level: NSWindow.Level) -> NSWindow {
        let w = NSWindow(contentRect: ns.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = level
        w.setFrame(ns.frame, display: false)
        return w
    }
    let desktop = window(NSWindow.Level(rawValue: level.rawValue - 1)), overlay = window(level)
    let canvas = NSView(), chrome = OverlayChrome(), container = NSView()
    for v in [canvas, desktop.contentView!] {
        v.wantsLayer = true
        v.layer?.contentsGravity = .resize
    }
    container.wantsLayer = true
    container.frame = CGRect(origin: .zero, size: ns.frame.size)
    for v in [canvas, chrome] as [NSView] {
        v.frame = CGRect(origin: .zero, size: ns.frame.size)
        v.autoresizingMask = [.width, .height]
        container.addSubview(v)
    }
    overlay.contentView = container

    let states: [(String, [Action])] = [
        ("empty", [.toggleOverview]), ("search", [.search("e")]), ("help", [.help]),
        ("toast", [.toggleOverview]), ("switcher", [.switchWindow(forward: true)]),
    ]
    var looks: [(String, GlassStyle, AccessibilityOptions)] = [("liquid", .liquid, .init()), ("frosted", .frosted, .init())]
    if args.contains("--accessibility") {
        looks += [("liquid-contrast", .liquid, .init(increaseContrast: true)), ("solid", .liquid, .init(reduceTransparency: true))]
    }
    for (lookName, glass, access) in looks {
        for (appearanceName, dark) in [("dark", true), ("light", false)] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for (name, actions) in states {
                var settings = loadSettings(ConfigPaths.standard()).settings
                settings.look.glass = glass
                let (layout, windows) = syntheticDesk([screen])
                var state = CanvasState(screens: [screen], settings: settings, ownPID: getpid(), now: 0, savedLayout: layout)
                for w in windows { _ = state.send(.system(.windowAppeared(w))) }
                if let first = windows.first { _ = state.send(.system(.windowFocused(first.id))) }
                Controller.applySystemLook(to: &state, dark: dark, accessibility: access)
                state.activeScreenID = screen.id
                let desk = state.scene(for: screen, time: 0)
                for a in actions { _ = state.send(.action(a)) }
                for step in 1 ... 480 { _ = state.send(.tick(Double(step) / 120)) }
                if name == "toast" { _ = state.send(.action(.arrange)) } // toasts last 1.8 s: raised once the overview has settled
                var scene = state.scene(for: screen, time: 4.2)
                let worldShown = state.isOverview
                let content = ChromeContent(taking: &scene, worldShown: worldShown)
                let picture = render(worldShown ? scene : desk, renderer, screen, scale: ns.backingScaleFactor)
                canvas.layer?.contents = worldShown ? picture : nil
                desktop.contentView?.layer?.contents = worldShown ? nil : picture
                chrome.show(content, transition: 1, opacity: 1)
                desktop.orderFrontRegardless()
                overlay.orderFrontRegardless()
                pump(1.2) // past the caret's off phase
                let f = ns.frame
                screencapture("0,0,\(Int(f.width)),\(Int(f.height))", to: out.appendingPathComponent("\(name)-\(lookName)-\(appearanceName).png"))
            }
        }
    }
    print(out.path)
    exit(0)
}

@MainActor
private func render(_ scene: Scene, _ renderer: Renderer, _ screen: ScreenInfo, scale: CGFloat) -> CGImage? {
    let frames = SyntheticFrames(windows: [], scale: 0.75)
    frames.update(scene.windows)
    return renderer.renderImage(scene, frames: frames, pixelSize: CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale))
}
