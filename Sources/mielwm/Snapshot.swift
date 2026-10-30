import AppKit
import MielCore
import MielRender
import MielSystem

/// Renders one state of one display to a PNG through the real Core and
/// Render, with synthetic windows or (`--real`) the user's own, captured as
/// stills and laid out from their real frames. Window commands are dropped.
@MainActor
func snapshot(_ args: [String]) {
    guard let out = value("--out", in: args) else {
        fail("usage: mielwm snapshot --state <state> [--real] [--screen n] [--light | --dark] [--workspaces] [--time s] --out x.png")
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
    state.systemAccent = Controller.systemAccent()
    state.systemDark = args.contains("--light") ? false : args.contains("--dark") ? true : Controller.systemDark()
    var access = Controller.accessibility()
    if args.contains("--reduce-transparency") { access.reduceTransparency = true }
    if args.contains("--increase-contrast") { access.increaseContrast = true }
    state.accessibility = access
    state.liquidGlassAvailable = Controller.liquidGlassAvailable
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
        try renderer.renderPNG(scene, frames: frames, to: URL(fileURLWithPath: out))
        print(out)
    } catch {
        fail("snapshot failed: \(error)")
    }
}

/// Three workspace frames for `--workspaces`: the screen's own (current),
/// one to its right and one below, as the tiling layout would place them.
func syntheticWorkspaces(_ screen: ScreenInfo) -> [SceneWorkspace] {
    let v = screen.visibleFrame.insetBy(dx: 8, dy: 8)
    return [
        SceneWorkspace(number: 1, canvasFrame: v, mode: .tiles, isCurrent: true, windowCount: 2),
        SceneWorkspace(number: 2, canvasFrame: v.offsetBy(dx: v.width + 160, dy: 0), mode: .stack, windowCount: 3),
        SceneWorkspace(number: 3, canvasFrame: v.offsetBy(dx: 0, dy: v.height + 160), mode: .tiles, windowCount: 1),
    ]
}

/// A believable desk: two windows on each display, the rest around it on the canvas.
func syntheticDesk(_ screens: [ScreenInfo]) -> (LayoutSnapshot, [WindowSnapshot]) {
    let apps = [
        ("Safari", "com.apple.Safari", "mielwm — GitHub"), ("Terminal", "com.apple.Terminal", "~/code/mielwm — fish"),
        ("Code", "com.microsoft.VSCode", "Renderer.swift — mielwm"), ("Notes", "com.apple.Notes", "Ideas for the canvas"),
        ("Finder", "com.apple.finder", "Downloads"), ("Mail", "com.apple.mail", "Inbox — 3 unread"),
        ("Calendar", "com.apple.iCal", "October 2026"), ("Music", "com.apple.Music", "Now Playing"),
        ("Preview", "com.apple.Preview", "barrel-lens.png"), ("TextEdit", "com.apple.TextEdit", "README.md"),
        ("Activity Monitor", "com.apple.ActivityMonitor", "CPU"), ("System Settings", "com.apple.systempreferences", "Displays"),
    ]
    let desk = deskRect(screens)
    var frames: [CGRect] = []
    for s in screens {
        let v = s.visibleFrame
        frames.append(CGRect(x: v.minX + v.width * 0.04, y: v.minY + v.height * 0.05, width: v.width * 0.55, height: v.height * 0.62).integral)
        frames.append(CGRect(x: v.minX + v.width * 0.44, y: v.minY + v.height * 0.33, width: v.width * 0.5, height: v.height * 0.58).integral)
    }
    let sizes = [CGSize(width: 1100, height: 720), CGSize(width: 860, height: 560), CGSize(width: 1000, height: 640), CGSize(width: 760, height: 900)]
    var k = 0
    while frames.count < apps.count { // a ring around the desk
        let angle = Double(k) * 2 * .pi / Double(apps.count - 2 * screens.count) + 0.4
        let size = sizes[k % sizes.count]
        let c = CGPoint(x: desk.midX + cos(angle) * desk.width * 0.85, y: desk.midY + sin(angle) * desk.height * 1.1)
        frames.append(CGRect(x: (c.x - size.width / 2).rounded(), y: (c.y - size.height / 2).rounded(), width: size.width, height: size.height))
        k += 1
    }
    let windows = apps.enumerated().map { i, app in
        WindowSnapshot(id: WindowID(pid: 90000 + Int32(i), number: UInt32(i + 1)), bundleID: app.1, appName: app.0, title: app.2,
                       frame: frames[i])
    }
    // Workspace 1 tiles the first two windows, workspace 2 stacks the next three, the rest float.
    let saved = windows.enumerated().map { i, w in
        SavedWindow(id: nil, bundleID: w.bundleID, appName: w.appName, title: w.title, ordinal: 0, frame: w.frame, deskFrame: w.frame,
                    parked: false, workspace: i < 2 ? 1 : i < 5 ? 2 : nil, position: i < 2 ? i : i - 2)
    }
    var layout = LayoutSnapshot(camera: Camera(center: desk.center), deskCenter: desk.center, windows: saved)
    layout.workspaces = [SavedWorkspace(slot: 2, mode: .stack, orientation: .auto)]
    return (layout, windows)
}
