import AppKit
import Carbon.HIToolbox
import MielCore
import MielRender
import MielSystem
import ScreenCaptureKit
import SwiftUI

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

// MARK: - mielwm <action>

/// Sends a command to the running app and prints its answer.
func send(_ args: [String]) -> Int32 {
    let text = args.joined(separator: " ")
    guard ["state", "quit"].contains(text) || Action(command: text) != nil else {
        fail("mielwm: unknown action '\(text)' (see mielwm --help)")
    }
    do {
        let data = try IPCClient.send(args, path: socketPath)
        print(String(decoding: data, as: UTF8.self))
        return data.starts(with: Data(#"{"error""#.utf8)) ? 1 : 0
    } catch IPCError.notRunning {
        fail("mielwm is not running (open mielwm.app first; mielwm --help lists the commands)")
    } catch {
        fail("mielwm: \(error)")
    }
}

// MARK: - --list-windows

@MainActor
func listWindows(json: Bool, fps: Bool, pid: Int32?) {
    _ = NSApplication.shared
    let screens = Displays.screens()
    let (windows, _) = readWindows(pid: pid)
    var onScreen: [UInt32: Bool] = [:]
    var done = false
    SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { content, _ in
        let pairs = (content?.windows ?? []).map { ($0.windowID, $0.isOnScreen) }
        DispatchQueue.main.async {
            onScreen = Dictionary(pairs, uniquingKeysWith: { a, _ in a })
            done = true
        }
    }
    spin(3) { done }

    // Frames per second each visible window's stream delivers, as the overview would see it.
    var rates: [WindowID: Double] = [:]
    if fps {
        let capture = CaptureManager()
        let visible = windows.filter { !isHiddenFrame($0.frame, screens: screens) && !$0.isMinimized }
        capture.setRate(.overview)
        for w in visible { capture.warm([w.id], maxPixelSize: w.frame.size) }
        spin(0.8)
        let start = Dictionary(visible.map { ($0.id, capture.generation(for: $0.id)) }, uniquingKeysWith: { a, _ in a })
        spin(2)
        for w in visible { rates[w.id] = Double(capture.generation(for: w.id) - start[w.id]!) / 2 }
        capture.stop(dropFrames: true)
    }

    if json {
        struct Row: Encodable {
            var id: String, pid: Int32, app: String, title: String, frame: [Double]
            var visible: Bool, managed: Bool, minimized: Bool, sckOnScreen: Bool?, fps: Double?
        }
        let rows = windows.map { w in
            Row(id: w.id.description, pid: w.id.pid, app: w.appName, title: w.title,
                frame: [w.frame.minX, w.frame.minY, w.frame.width, w.frame.height],
                visible: !isHiddenFrame(w.frame, screens: screens), managed: w.isStandard && w.isMovable, minimized: w.isMinimized,
                sckOnScreen: onScreen[w.id.number], fps: rates[w.id])
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: (try? encoder.encode(rows)) ?? Data(), as: UTF8.self))
        return
    }
    for s in screens {
        print("screen \(s.id) \(s.name): frame \(fmt(s.frame)) visible \(fmt(s.visibleFrame)) @\(Int(s.scale))x")
    }
    for w in windows {
        var flags = [isHiddenFrame(w.frame, screens: screens) ? "hidden" : "visible"]
        if !w.isStandard { flags.append("not-standard") }
        if !w.isMovable { flags.append("not-movable") }
        if w.isMinimized { flags.append("minimized") }
        if onScreen[w.id.number] == false { flags.append("sck-offscreen") }
        if let r = rates[w.id] { flags.append(String(format: "%.0ffps", r)) }
        let title = w.title.isEmpty ? "" : " “\(w.title)”"
        print("\(w.id)\t\(w.appName)\(title)\t\(fmt(w.frame))\t\(flags.joined(separator: " "))")
    }
}

func fmt(_ r: CGRect) -> String {
    String(format: "%.0f,%.0f %.0fx%.0f", r.minX, r.minY, r.width, r.height)
}

// MARK: - --unpark and --watch

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
    print("mielwm: unparked \(commands.count) windows\(ok ? "" : " (some apps did not answer)")")
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

// MARK: - snapshot

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

// MARK: - --settings-preview

/// Opens the Settings window, the onboarding and About without the canvas
/// (no event tap, nothing moves), saves each as a PNG in light and dark,
/// then quits. It works on a copy of the config, so nothing it does is saved.
/// `--live <pane>` instead leaves the Settings window on screen for 10 s
/// and prints its window number, for `screencapture -l`.
@MainActor
func settingsPreview(_ args: [String]) -> Never {
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApp.applicationIconImage = appIcon()
    let fm = FileManager.default
    let out = URL(fileURLWithPath: value("--out", in: args) ?? "settings-preview", isDirectory: true)
    let scratch = fm.temporaryDirectory.appendingPathComponent("mielwm-settings-preview-\(getpid())", isDirectory: true)
    try? fm.createDirectory(at: out, withIntermediateDirectories: true)
    try? fm.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: scratch) }
    let real = ConfigPaths.standard()
    let paths = ConfigPaths(config: scratch.appendingPathComponent("config.json"))
    try? fm.copyItem(at: real.config, to: paths.config)

    let model = SettingsModel(paths: paths, remembersPane: false)
    let settings = SettingsWindow(model: model)
    if let pane = value("--live", in: args).flatMap(SettingsPane.init) {
        if args.contains("--light") { NSApp.appearance = NSAppearance(named: .aqua) }
        // A real event loop: without NSApp.run the window is never redrawn after its first frame.
        func after(_ seconds: Double, _ step: @escaping @MainActor () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated(step) }
        }
        settings.show(pane)
        var at = 1.5
        if let then = value("--then", in: args).flatMap(SettingsPane.init) { // a second pane, as a click would
            if args.contains("--reopen") {
                after(at) { settings.window.close() }
                after(at + 0.5) { settings.show() }
                at += 1
            }
            after(at) { model.pane = then }
            at += 1
        }
        after(at) {
            // A window in the background draws its sidebar opaque; show it as it looks in front.
            @MainActor func activate(_ v: NSView) {
                (v as? NSVisualEffectView)?.state = .active
                v.subviews.forEach(activate)
            }
            settings.window.contentView?.superview.map(activate)
            // Bold stripes just behind the window, so its translucency shows in a screenshot.
            if args.contains("--stripes") {
                let stripes = NSWindow(contentRect: settings.window.frame.insetBy(dx: -40, dy: -40), styleMask: .borderless, backing: .buffered, defer: false)
                stripes.contentView = NSHostingView(rootView: HStack(spacing: 0) {
                    ForEach(0 ..< 16) { i in Color(hue: Double(i) / 16, saturation: 0.8, brightness: 0.95) }
                })
                stripes.level = .floating
                stripes.orderFrontRegardless()
            }
            settings.window.level = NSWindow.Level(NSWindow.Level.floating.rawValue + 1) // above the app in front, for a screenshot of the screen
            settings.window.orderFrontRegardless()
        }
        after(at + 0.5) {
            let f = settings.window.frame, top = NSScreen.screens.first?.frame.maxY ?? f.maxY
            print(settings.window.windowNumber, "\(Int(f.minX)),\(Int(top - f.maxY)),\(Int(f.width)),\(Int(f.height))")
            fflush(stdout)
        }
        after(at + 10) { exit(0) }
        NSApp.run()
    }
    if args.contains("--selftest") {
        settingsSelfTest(model, settings, paths)
    }
    let note = AeroSpaceImport.standardURL().flatMap { try? String(contentsOf: $0, encoding: .utf8) }.map {
        var found = AeroSpaceImport(toml: $0)
        found.bindings = [:]
        return aeroSpaceImportNote(found)
    }
    let onboarding = Onboarding.makeWindow(OnboardingModel(note: note))
    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        NSApp.appearance = NSAppearance(named: appearance)
        for pane in SettingsPane.allCases {
            settings.show(pane)
            pump(pane == .appearance ? 1.5 : 0.8)
            let file = "settings-\(pane.rawValue)-\(name)"
            savePNG(settings.window, to: out.appendingPathComponent(file + ".png"))
            // A pane taller than the window: its end too.
            if let scroll = detailScrollView(in: settings.window.contentView), let doc = scroll.documentView,
               doc.frame.height > scroll.contentView.bounds.height + 1 {
                doc.scroll(NSPoint(x: 0, y: doc.isFlipped ? doc.frame.height : 0))
                pump(0.4)
                savePNG(settings.window, to: out.appendingPathComponent(file + "-end.png"))
            }
        }
        // The AeroSpace import, as the Layout pane asks about it.
        if let toml = AeroSpaceImport.standardURL().flatMap({ try? String(contentsOf: $0, encoding: .utf8) }) {
            settings.show(.layout)
            pump(0.5)
            model.aeroSpaceFound = AeroSpaceImport(toml: toml)
            pump(0.8)
            if let sheet = settings.window.attachedSheet ?? NSApp.windows.first(where: { $0.isVisible && $0.isSheet }) {
                savePNG(sheet, to: out.appendingPathComponent("import-\(name).png"))
            }
            model.aeroSpaceFound = nil
            pump(0.5)
        }
        // The Keyboard pane's states: a custom family open, a recorder listening, a conflict.
        let saved = try? Data(contentsOf: paths.config)
        model.apply(["keys:opt+3": .text("none"), "keys:ctrl+opt+3": .text("workspace 3")])
        model.expanded = [.workspace]
        model.recording = ShortcutSlot(target: .family(.focus), chord: nil)
        model.held = [.control, .option]
        model.conflict = ShortcutConflict(slot: ShortcutSlot(target: .family(.nudge), chord: nil), changes: model.settings.rebind(.nudge, to: .control),
                                          chords: [KeyChord("ctrl+left")!, KeyChord("ctrl+right")!],
                                          others: [.workspaceStep(forward: false), .workspaceStep(forward: true)])
        settings.show(.keyboard)
        pump(0.8)
        for (part, y) in [(1, 600.0), (2, 1250.0)] {
            if let scroll = detailScrollView(in: settings.window.contentView), let doc = scroll.documentView {
                doc.scroll(NSPoint(x: 0, y: doc.isFlipped ? y : doc.frame.height - y - scroll.contentView.bounds.height))
                pump(0.4)
            }
            savePNG(settings.window, to: out.appendingPathComponent("settings-keyboard-states\(part)-\(name).png"))
        }
        model.recording = nil
        model.conflict = nil
        model.expanded = []
        if let saved { try? saved.write(to: paths.config) } else { try? fm.removeItem(at: paths.config) }
        model.reload()
        settings.window.orderOut(nil)

        onboarding.center()
        onboarding.makeKeyAndOrderFront(nil)
        pump(0.6)
        savePNG(onboarding, to: out.appendingPathComponent("onboarding-\(name).png"))
        onboarding.orderOut(nil)

        NSApp.orderFrontStandardAboutPanel(options: aboutOptions)
        pump(0.6)
        if let about = NSApp.windows.first(where: { $0.isVisible && $0 !== settings.window && $0 !== onboarding }) {
            savePNG(about, to: out.appendingPathComponent("about-\(name).png"))
            about.close()
        }
        saveMenuBarPreview(dark: name == "dark", to: out.appendingPathComponent("menubar-\(name).png"))
        for (file, alert) in [("alert-aerospace", AppDelegate.aeroSpaceAlert(swipe: true, note: nil)),
                              ("alert-config", AppDelegate.configProblemsAlert(["config.json: unknown setting 'canvas:grid_colour'"]))] {
            alert.layout()
            savePNG(alert.window, to: out.appendingPathComponent("\(file)-\(name).png"))
        }
        let blocked = OnboardingModel(note: nil)
        blocked.accessibility = false
        blocked.recording = false
        let first = Onboarding.makeWindow(blocked)
        first.center()
        first.makeKeyAndOrderFront(nil)
        pump(0.6)
        savePNG(first, to: out.appendingPathComponent("onboarding-first-\(name).png"))
        first.orderOut(nil)
        if args.contains("--menu") { saveMenuPreview(to: out.appendingPathComponent("menu-\(name).png")) }
    }
    print(out.path)
    exit(0)
}

/// The status menu, popped up for a moment and captured from the screen
/// (an open menu can't be drawn offscreen). Needs Screen Recording for the terminal.
@MainActor
private func saveMenuPreview(to url: URL) {
    let menu = AppDelegate(mode: .normal).previewMenu(Controller(mode: .manageOnly(0)))
    guard let screen = NSScreen.main else { return }
    let at = NSPoint(x: screen.frame.midX - 120, y: screen.frame.midY + 150)
    let rect = "\(Int(at.x) - 12),\(Int(screen.frame.maxY - at.y) - 12),\(Int(menu.size.width) + 24),\(Int(menu.size.height) + 24)"
    nonisolated(unsafe) let open = menu // the timer fires on the main thread, inside the menu's tracking loop
    let timer = Timer(timeInterval: 0.6, repeats: false) { _ in
        let shot = Process()
        shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        shot.arguments = ["-x", "-R", rect, url.path]
        try? shot.run()
        shot.waitUntilExit()
        open.cancelTracking()
    }
    RunLoop.main.add(timer, forMode: .common)
    menu.popUp(positioning: nil, at: at, in: nil)
}

/// The workspace indicator and the icon as the menu bar tints them: 2x on the left, 1x (scaled up) on the right.
@MainActor
private func saveMenuBarPreview(dark: Bool, to url: URL) {
    let cases: [([Int], Int?)] = [([1, 2, 3, 5, 9], 3), ([1], 1), ([2, 4], 4), ([1, 2, 3, 4, 5, 6, 7, 8, 9], 9)]
    let images = cases.map { workspaceIndicator($0.0, current: $0.1) } + [menuBarIconImage].compactMap { $0 }
    let ink = dark ? NSColor.white : NSColor.black
    let columnWidth = images.map(\.size.width).max()! + 16, rowHeight: CGFloat = 24
    let points = NSSize(width: columnWidth * 2 + 16, height: rowHeight * CGFloat(images.count) + 8)
    guard let canvas = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(points.width) * 2, pixelsHigh: Int(points.height) * 2,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    canvas.size = points
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
    NSGraphicsContext.current?.imageInterpolation = .none
    (dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
    NSRect(origin: .zero, size: points).fill()
    for (row, image) in images.enumerated() {
        let tinted = NSImage(size: image.size, flipped: false) { r in
            image.draw(in: r)
            ink.set()
            r.fill(using: .sourceAtop)
            return true
        }
        let y = points.height - 4 - CGFloat(row + 1) * rowHeight + (rowHeight - image.size.height) / 2
        tinted.draw(in: NSRect(origin: NSPoint(x: 8, y: y), size: image.size))
        // 1x: drawn into a 1x bitmap first, so its pixels show.
        if let small = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width.rounded(.up)), pixelsHigh: Int(image.size.height),
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: small)
            tinted.draw(in: NSRect(origin: .zero, size: image.size))
            NSGraphicsContext.restoreGraphicsState()
            small.draw(in: NSRect(origin: NSPoint(x: 8 + columnWidth + 8, y: y), size: image.size), from: .zero,
                       operation: .sourceOver, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.none.rawValue])
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    try? canvas.representation(using: .png, properties: [:])?.write(to: url)
}

/// Drives the Settings window's model and recorders the way a person would,
/// with key events posted to this process only, on a copy of the config.
/// Prints each check; exits 1 if one fails.
@MainActor
private func settingsSelfTest(_ model: SettingsModel, _ window: SettingsWindow, _ paths: ConfigPaths) -> Never {
    var failed = 0
    func check(_ ok: Bool, _ what: String) {
        print(ok ? "ok    " : "FAILED", what)
        if !ok { failed += 1 }
    }
    func file() -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(contentsOf: paths.config))) as? [String: Any] ?? [:]
    }
    func key(_ code: Int, _ mods: NSEvent.ModifierFlags = [], _ chars: String = "") {
        for type in [NSEvent.EventType.flagsChanged, .keyDown] where type == .keyDown || !mods.isEmpty {
            let e = type == .flagsChanged
                ? NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: window.window.windowNumber,
                                   context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 58)
                : NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: window.window.windowNumber,
                                   context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: UInt16(code))
            NSApp.postEvent(e!, atStart: false)
            pump(0.05)
        }
    }
    var live: [MielCore.Settings] = []
    var writes = 0
    model.onLive = { live.append($0) }
    model.onWrite = { writes += 1 }
    window.show(.keyboard)
    pump(0.5)

    // The user's own config shows as it is.
    check(model.settings == loadSettings(paths).settings, "the window shows config.json as it is")

    // Accent: a swatch writes the file, the canvas gets it at once, a reload keeps it.
    model.set("navigator:accent", .text("green"))
    check(live.last?.accent == "green" && writes == 0, "accent reaches the canvas before the file")
    pump(0.4)
    check(file()["navigator:accent"] as? String == "green" && writes == 1, "accent written once, after a pause")
    check(model.settings.resolvedLook().accent == parseHexColor("#3ddc84"), "accent resolves to the preset")
    model.set("navigator:accent", .text("auto"))
    model.flush()
    check(file()["navigator:accent"] == nil, "automatic leaves the file")
    // A slider dragged: many steps, one write.
    writes = 0
    for v in stride(from: 0.1, through: 0.3, by: 0.01) { model.set("distortion:strength", .number(v)) }
    pump(0.4)
    check(writes == 1 && (file()["distortion:strength"] as? Double).map { abs($0 - 0.3) < 0.001 } == true, "a dragged slider writes once")
    // An edit to the file shows up while the window is open.
    var edited = file()
    edited["navigator:accent"] = "teal"
    try? JSONSerialization.data(withJSONObject: edited).write(to: paths.config)
    pump(1.6)
    check(model.settings.accent == "teal", "an outside edit shows up")

    // Every control's key: a value that is not the default goes to the file and comes back from it.
    let values: [(String, SettingValue)] = [
        ("animation:enabled", .flag(false)), ("blur", .flag(true)), ("canvas:grid_enabled", .flag(false)),
        ("canvas:minimap_enabled", .flag(true)), // the user's file has it off: on is the default, so it leaves ("canvas:remember_layout", .flag(false)), ("distortion:enabled", .flag(false)),
        ("menubar:workspaces", .flag(false)), ("navigator:labels", .flag(false)), ("navigator:pointer", .flag(false)),
        ("wallpaper", .flag(false)), ("window:shadow", .flag(false)), ("blur_strength", .number(0.4)),
        ("canvas:background_dim", .number(0.5)), ("canvas:grid_opacity", .number(0.3)), ("canvas:initial_zoom", .number(0.5)),
        ("distortion:edge_scale", .number(1.3)), ("distortion:strength", .number(0.2)), ("window:rounding", .number(20)),
        ("animation:speed", .number(2)), ("layout:default", .text("stack")), ("layout:orientation", .text("vertical")),
        ("canvas:grid_style", .text("lines")), ("layout:floating_apps", .text("com.apple.finder")),
        ("layout:workspace_rules", .text("com.apple.finder=4")), ("navigator:accent", .text("#123456")),
        ("gaps:inner_horizontal", .number(20)), ("gaps:inner_vertical", .number(22)), ("gaps:outer_left", .number(4)),
        ("gaps:outer_right", .number(6)), ("gaps:outer_bottom", .number(30)), ("gaps:outer_top", .number(2)),
        ("gaps:outer_top_external", .number(40)),
    ]
    for (key, value) in values { model.set(key, value) }
    model.flush()
    let reread = loadSettings(paths)
    let wrong = values.filter { reread.settings.value(forKey: $0.0) != $0.1 || model.settings.value(forKey: $0.0) != $0.1 }.map(\.0)
    check(wrong.isEmpty && reread.errors.isEmpty && values.allSatisfy { (file()[$0.0] != nil) == (MielCore.Settings().value(forKey: $0.0) != $0.1) }, "every control round-trips through the file" + (wrong.isEmpty ? "" : " \(wrong)"))
    for (key, _) in values { model.set(key, MielCore.Settings().value(forKey: key)!) }
    model.flush()
    check(values.allSatisfy { file()[$0.0] == nil }, "every control back at its default leaves the file")

    // A shortcut: click, press keys.
    model.startRecording(ShortcutSlot(target: .action(.pin), chord: KeyChord("opt+o")))
    key(kVK_ANSI_P, [.control, .option], "p")
    check(model.recording == nil && model.settings.chords(for: .pin) == [KeyChord("ctrl+opt+p")!], "⌃⌥P replaces ⌥O for pin")
    check(file()["keys:opt+o"] as? String == "none" && file()["keys:ctrl+opt+p"] as? String == "pin", "written as none + pin")
    model.startRecording(ShortcutSlot(target: .action(.pin), chord: KeyChord("ctrl+opt+p")))
    key(kVK_ANSI_L, [], "l")
    check(model.recording != nil, "a plain letter is refused, still recording")
    key(kVK_ANSI_Q, [.command], "q")
    check(model.recording != nil, "⌘Q is refused")
    key(kVK_Escape)
    check(model.recording == nil && model.settings.chords(for: .pin) == [KeyChord("ctrl+opt+p")!], "Esc cancels")
    model.startRecording(ShortcutSlot(target: .action(.pin), chord: KeyChord("ctrl+opt+p")))
    key(kVK_Delete)
    check(model.settings.chords(for: .pin).isEmpty, "Delete clears")
    model.startRecording(ShortcutSlot(target: .action(.pin), chord: nil))
    key(kVK_ANSI_O, [.option], "o")
    check(model.settings.chords(for: .pin) == [KeyChord("opt+o")!] && file()["keys:opt+o"] == nil, "the default again leaves the file")

    // A family: modifiers, then any of its keys.
    model.startRecording(ShortcutSlot(target: .family(.workspace), chord: nil))
    key(kVK_ANSI_5, [.control, .option], "5")
    check(model.settings.binding(of: .workspace) == .modifiers([.control, .option]), "⌃⌥ + a digit sets all nine")
    model.startRecording(ShortcutSlot(target: .family(.workspace), chord: nil))
    key(kVK_ANSI_5, [.shift], "%")
    check(model.recording != nil, "⇧ alone is refused")
    key(kVK_ANSI_A, [.option], "a")
    check(model.recording != nil, "a key outside the family is refused")
    key(kVK_Return, [.option])
    check(model.recording == nil && model.settings.binding(of: .workspace) == .modifiers(.option), "⌥↩ confirms ⌥ (back to the default)")
    // Taking keys another action has: asks first.
    model.startRecording(ShortcutSlot(target: .family(.nudge), chord: nil))
    key(kVK_LeftArrow, [.control])
    check(model.conflict?.others.count == 2 && model.settings.binding(of: .nudge) == .modifiers([.option, .shift]), "⌃ arrows ask about the workspace keys")
    if let c = model.conflict {
        model.conflict = nil
        model.apply(c.changes)
    }
    check(model.settings.binding(of: .nudge) == .modifiers(.control) && model.settings.chords(for: .workspaceStep(forward: true)).isEmpty,
          "Use here moves them")
    check(loadSettings(paths).errors.isEmpty, "the file still loads cleanly")
    model.apply(model.settings.restoreDefaults(for: nil))
    check(model.settings.bindings == MielCore.Settings().bindings, "Restore defaults")

    // The command-line tool, into a scratch ~/.local/bin.
    let link = paths.config.deletingLastPathComponent().appendingPathComponent("bin/\(CLITool.name)")
    check(CLITool.status(link: link) == .missing, "tool: missing")
    check((try? CLITool.install(link: link)).map { if case .installed = $0 { true } else { false } } == true, "tool: installed")
    check(CLITool.remove(link: link) == .missing, "tool: removed")
    try? Data().write(to: link)
    check(CLITool.status(link: link) != .missing && CLITool.remove(link: link) != .missing, "tool: someone else's file is left alone")

    print(failed == 0 ? "all passed" : "\(failed) failed")
    exit(failed == 0 ? 0 : 1)
}

/// Runs AppKit's event loop for `seconds`, as NSApp.run would: windows
/// lay out and redraw, monitors see events.
@MainActor
private func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        if let event = NSApp.nextEvent(matching: .any, until: min(end, Date().addingTimeInterval(0.02)), inMode: .default, dequeue: true) {
            NSApp.sendEvent(event)
        }
        NSApp.updateWindows()
    }
}

/// The detail pane's scroll view (the sidebar has one too).
private func detailScrollView(in view: NSView?) -> NSScrollView? {
    guard let view else { return nil }
    var all: [NSScrollView] = []
    func walk(_ v: NSView) {
        if let s = v as? NSScrollView { all.append(s) }
        v.subviews.forEach(walk)
    }
    walk(view)
    return all.max { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
}

/// The whole window, title bar and toolbar included.
@MainActor
private func savePNG(_ window: NSWindow, to url: URL) {
    guard let view = window.contentView?.superview, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
}
