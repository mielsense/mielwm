import AppKit
import MielCore
import MielRender
import MielSystem
import SwiftUI

/// Renders one state of one display to a PNG through the real Core and
/// Render, with synthetic windows or (`--real`) the user's own, captured as
/// stills and laid out from their real frames. Window commands are dropped.
@MainActor
func snapshot(_ args: [String]) {
    guard let out = value("--out", in: args) else {
        fail("usage: mielwm snapshot --state <state> [--real [--pid n]] [--screen n] [--fake-external] [--light | --dark] [--reduce-transparency] [--increase-contrast] [--workspaces] [--time s] --out x.png")
    }
    let stateName = value("--state", in: args) ?? "overview"
    let real = args.contains("--real")
    _ = NSApplication.shared
    var screens = Displays.screens()
    guard let primary = screens.first else { fail("no displays") }
    if args.contains("--fake-external") { // the 1080p display to the right, when it is unplugged
        screens.append(ScreenInfo(id: 0xE0, name: "External 1080p (simulated)", frame: CGRect(x: primary.frame.maxX, y: 0, width: 1920, height: 1080),
                                  visibleFrame: CGRect(x: primary.frame.maxX, y: 25, width: 1920, height: 1055), scale: 1))
    }
    let index = Int(value("--screen", in: args) ?? "0") ?? 0
    guard screens.indices.contains(index) else { fail("--screen takes 0...\(screens.count - 1)") }
    let screen = screens[index]

    let action: Action?
    var then: Action? // overview:<command>: open the overview, then that (e.g. "overview:workspace 4")
    switch stateName {
    case "desktop": action = nil
    case "overview": action = .toggleOverview
    case "help": action = .help
    case "switcher": action = .switchWindow(forward: true)
    case let s where s.hasPrefix("search:"): action = .search(String(s.dropFirst(7)))
    case let s where s.hasPrefix("overview:"):
        action = .toggleOverview
        guard let a = Action(command: String(s.dropFirst(9))) else { fail("unknown command in '\(s)'") }
        then = a
    default: fail("unknown state '\(stateName)': desktop, overview, overview:<command>, search:<q>, switcher or help")
    }

    let settings = loadSettings(ConfigPaths.standard()).settings
    var state: CanvasState
    let frames: WindowFrameSource
    if real {
        let (windows, focused) = readWindows(pid: value("--pid", in: args).flatMap { Int32($0) })
        state = CanvasState(screens: screens, settings: settings, ownPID: getpid(), now: 0)
        for w in windows { _ = state.send(.system(.windowAppeared(w))) }
        if let focused { _ = state.send(.system(.windowFocused(focused))) }
        let capture = CaptureManager()
        var done = false
        capture.captureStills(state.windows.map(\.id), scale: 0.75) { done = true }
        spin(8) { done }
        frames = capture
    } else {
        let (layout, windows) = syntheticDesk(screens)
        state = CanvasState(screens: screens, settings: settings, ownPID: getpid(), now: 0, savedLayout: layout)
        for w in windows { _ = state.send(.system(.windowAppeared(w))) }
        if let first = windows.first { _ = state.send(.system(.windowFocused(first.id))) }
        frames = SyntheticFrames(windows: [], scale: screen.scale)
    }
    var access = Controller.accessibility()
    if args.contains("--reduce-transparency") { access.reduceTransparency = true }
    if args.contains("--increase-contrast") { access.increaseContrast = true }
    Controller.applySystemLook(to: &state, dark: args.contains("--light") ? false : args.contains("--dark") ? true : nil, accessibility: access)
    state.activeScreenID = screen.id
    if let action { _ = state.send(.action(action)) }
    if let then { _ = state.send(.action(then)) }
    // Four seconds by default: every flight has landed. `--time` stops earlier, mid-flight.
    let seconds = value("--time", in: args).flatMap(Double.init) ?? 4
    for step in 1 ... max(1, Int((seconds * 120).rounded())) { _ = state.send(.tick(Double(step) / 120)) }

    var scene = state.scene(for: screen, time: seconds + 0.2)
    if args.contains("--workspaces"), scene.workspaces.isEmpty { scene.workspaces = syntheticWorkspaces(screen) }
    (frames as? SyntheticFrames)?.update(scene.windows)
    do {
        let renderer = try Renderer()
        var wallpaper: CGImage?, done = false
        MielSystem.Wallpaper.image(for: screen) { wallpaper = $0; done = true }
        spin(5) { done }
        renderer.setWallpaper(wallpaper, screenID: screen.id)
        let chrome = ChromeContent(taking: &scene, worldShown: state.isOverview)
        guard let canvas = renderer.renderImage(scene, frames: frames),
              let image = withChrome(canvas, chrome, transition: scene.transition, scale: screen.scale)
        else { fail("snapshot failed: nothing rendered") }
        try Renderer.writePNG(image, to: URL(fileURLWithPath: out))
        print(out)
    } catch {
        fail("snapshot failed: \(error)")
    }
}

/// `canvas` with the overview's native chrome drawn over it, as the overlay stacks them.
@MainActor
private func withChrome(_ canvas: CGImage, _ content: ChromeContent, transition: Double, scale: CGFloat) -> CGImage? {
    let (eased, steady) = OverlayChrome.split(content)
    let renderer = ImageRenderer(content: ZStack {
        EasedChrome(model: ChromeModel(eased)).opacity(OverlayChrome.easedAlpha(transition))
        SteadyChrome(model: ChromeModel(steady))
    }.environment(\.chromeStill, true))
    renderer.scale = scale
    guard let chrome = renderer.cgImage,
          let ctx = CGContext(data: nil, width: canvas.width, height: canvas.height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    else { return nil }
    let all = CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
    ctx.draw(canvas, in: all)
    ctx.draw(chrome, in: all)
    return ctx.makeImage()
}
