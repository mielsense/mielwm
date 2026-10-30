import AppKit
import MielCore
import MielSystem
import SwiftUI

/// Opens the Settings window, the onboarding and About without the canvas
/// (no event tap, nothing moves), saves each as a PNG in light and dark,
/// then quits. It works on a copy of the config, so nothing it does is saved.
/// `--live <pane> [--search <text>]` instead leaves the Settings window on screen for 10 s
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
        if let query = value("--search", in: args) { model.paneQuery = query } // the sidebar's search, typed in
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
            // The glass style picker sits where the first view ends: a view of it on its own.
            if pane == .appearance, let scroll = detailScrollView(in: settings.window.contentView), let doc = scroll.documentView {
                let y = 420.0
                doc.scroll(NSPoint(x: 0, y: doc.isFlipped ? y : doc.frame.height - y - scroll.contentView.bounds.height))
                pump(0.4)
                savePNG(settings.window, to: out.appendingPathComponent(file + "-glass.png"))
            }
        }
        // The AeroSpace import, as the AeroSpace & Barik pane asks about it.
        if let toml = AeroSpaceImport.standardURL().flatMap({ try? String(contentsOf: $0, encoding: .utf8) }) {
            settings.show(.integrations)
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
        // The Layout pane's diagram and top edge rows: with the status bar this display has (found), and with a sample one.
        settings.show(.layout)
        pump(0.8)
        let found = model.screen?.topBar
        for (file, bar) in [("found", found), ("sample", TopBar(owner: "Barik", height: 40))] {
            model.screen?.topBar = bar
            for (part, y) in [("diagram", 0.0), ("gaps", 380.0)] {
                if let scroll = detailScrollView(in: settings.window.contentView), let doc = scroll.documentView {
                    doc.scroll(NSPoint(x: 0, y: doc.isFlipped ? y : doc.frame.height - y - scroll.contentView.bounds.height))
                }
                pump(0.5)
                savePNG(settings.window, to: out.appendingPathComponent("settings-layout-\(part)-\(file)-\(name).png"))
            }
        }
        // The sidebar's search, and the Keyboard pane's.
        model.paneQuery = "gap"
        pump(0.5)
        savePNG(settings.window, to: out.appendingPathComponent("settings-search-\(name).png"))
        model.paneQuery = ""
        model.keyQuery = "workspace"
        settings.show(.keyboard)
        pump(0.6)
        savePNG(settings.window, to: out.appendingPathComponent("settings-keyboard-search-\(name).png"))
        model.keyQuery = ""
        if let saved { try? saved.write(to: paths.config) } else { try? fm.removeItem(at: paths.config) }
        model.reload()
        settings.window.orderOut(nil)

        onboarding.center()
        onboarding.makeKeyAndOrderFront(nil)
        pump(0.6)
        savePNG(onboarding, to: out.appendingPathComponent("onboarding-\(name).png"))
        onboarding.orderOut(nil)

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
    let controller = Controller(mode: .manageOnly(0))
    // A window from each of the first open apps, spread over workspaces 1 to 3, so the menu lists them.
    let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }.prefix(6)
    let screen = controller.state.screens.first?.visibleFrame ?? .zero
    controller.state.settings.defaultLayout = .tiles
    controller.state.settings.workspaceRules = apps.enumerated().map { "\($1.bundleIdentifier!)=\([1, 1, 1, 2, 3, 3][$0])" }.joined(separator: ",")
    _ = controller.state.send(.tick(controller.state.now + 20))
    for (i, app) in apps.enumerated() {
        _ = controller.state.send(.system(.windowAppeared(WindowSnapshot(id: WindowID(pid: app.processIdentifier, number: UInt32(i + 1)), bundleID: app.bundleIdentifier,
                                                                         appName: app.localizedName ?? "", title: "", frame: screen.insetBy(dx: 100, dy: 100)))))
    }
    _ = controller.state.send(.action(.workspace(1)))
    let menu = AppDelegate(mode: .normal).previewMenu(controller)
    guard let screen = NSScreen.main else { return }
    let at = NSPoint(x: screen.frame.midX - 120, y: screen.frame.midY + 150)
    let rect = "\(Int(at.x) - 12),\(Int(screen.frame.maxY - at.y) - 12),\(Int(menu.size.width) + 24),\(Int(menu.size.height) + 24)"
    nonisolated(unsafe) let open = menu // the timer fires on the main thread, inside the menu's tracking loop
    let timer = Timer(timeInterval: 0.6, repeats: false) { _ in
        screencapture(rect, to: url)
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
