import CoreGraphics
import Foundation
import MielCore

/// Two displays as on the user's desk: the notched built-in Retina panel and
/// a 1080p external to its right, with a dozen windows across both.
enum Fixture {
    static let retina = ScreenInfo(id: 1, name: "Built-in Retina Display", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                   visibleFrame: CGRect(x: 0, y: 38, width: 1512, height: 944), scale: 2, safeAreaTop: 32, isBuiltIn: true)
    static let external = ScreenInfo(id: 2, name: "DELL U2419H", frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
                                     visibleFrame: CGRect(x: 1512, y: 25, width: 1920, height: 1055), scale: 1)
    static let screens = [retina, external]
    static let desk = retina.frame.union(external.frame)

    private static func window(_ n: UInt32, _ app: String, _ bundle: String, _ title: String, _ frame: CGRect) -> SceneWindow {
        SceneWindow(id: WindowID(pid: Int32(100 + n), number: n), canvasFrame: frame, title: title, appName: app, bundleID: bundle)
    }

    /// Canvas frames for the zoomed-out view.
    static let canvasWindows: [SceneWindow] = [
        window(1, "Safari", "com.apple.Safari", "mielwm — GitHub", CGRect(x: -2150, y: -560, width: 1280, height: 820)),
        window(2, "Terminal", "com.apple.Terminal", "~/code/mielwm — fish", CGRect(x: -700, y: -520, width: 860, height: 560)),
        window(3, "Notes", "com.apple.Notes", "Ideas for the canvas", CGRect(x: -2100, y: 420, width: 760, height: 900)),
        window(4, "Finder", "com.apple.finder", "Downloads", CGRect(x: -1180, y: 220, width: 980, height: 640)),
        window(5, "Mail", "com.apple.mail", "Inbox — 3 unread", CGRect(x: -80, y: 300, width: 1100, height: 720)),
        window(6, "Code", "com.microsoft.VSCode", "Renderer.swift — mielwm", CGRect(x: 400, y: -600, width: 1400, height: 860)),
        window(7, "Calendar", "com.apple.iCal", "October 2026", CGRect(x: 2050, y: -560, width: 1200, height: 800)),
        window(8, "Music", "com.apple.Music", "Now Playing", CGRect(x: 3450, y: -480, width: 1000, height: 640)),
        window(9, "Preview", "com.apple.Preview", "barrel-lens.png", CGRect(x: 4650, y: -520, width: 900, height: 700)),
        window(10, "TextEdit", "com.apple.TextEdit", "README.md", CGRect(x: 1400, y: 460, width: 900, height: 1000)),
        window(11, "Activity Monitor", "com.apple.ActivityMonitor", "CPU", CGRect(x: 2500, y: 520, width: 1100, height: 700)),
        window(12, "System Settings", "com.apple.systempreferences", "Displays", CGRect(x: 3850, y: 420, width: 1000, height: 760)),
    ]

    /// Desk frames at zoom 1: three on the Retina panel, one across the
    /// seam, two on the external display. (0, 0) of each screen stays clear.
    static let deskWindows: [SceneWindow] = [
        window(1, "Safari", "com.apple.Safari", "mielwm — GitHub", CGRect(x: 60, y: 120, width: 900, height: 620)),
        window(2, "Terminal", "com.apple.Terminal", "~/code/mielwm — fish", CGRect(x: 820, y: 420, width: 620, height: 400)),
        window(4, "Finder", "com.apple.finder", "Downloads", CGRect(x: 200, y: 560, width: 560, height: 360)),
        window(6, "Code", "com.microsoft.VSCode", "Renderer.swift — mielwm", CGRect(x: 1180, y: 80, width: 900, height: 600)),
        window(7, "Calendar", "com.apple.iCal", "October 2026", CGRect(x: 2200, y: 140, width: 1000, height: 700)),
        window(10, "TextEdit", "com.apple.TextEdit", "README.md", CGRect(x: 2600, y: 600, width: 600, height: 420)),
    ]

    static let overviewCamera = Camera(center: desk.center, zoom: 0.42)

    static func minimap(_ windows: [SceneWindow], camera: Camera, focused: Int?) -> MinimapModel {
        MinimapModel(windows: windows.map { ($0.canvasFrame, $0.dim) }, focusedIndex: focused,
                     viewport: camera.toCanvas(desk, deskCenter: desk.center))
    }

    /// Two workspace frames around the Retina panel's windows and one stack.
    static let workspaces = [
        SceneWorkspace(number: 1, canvasFrame: CGRect(x: -2200, y: -620, width: 2420, height: 1960), mode: .tiles, isCurrent: true, windowCount: 5),
        SceneWorkspace(number: 2, canvasFrame: CGRect(x: 380, y: -640, width: 1960, height: 2140), mode: .stack, windowCount: 3),
    ]

    static func overview(_ screen: ScreenInfo, look: Look = Look(), windows: [SceneWindow] = canvasWindows,
                         selected: WindowID? = WindowID(pid: 106, number: 6)) -> Scene {
        var windows = windows
        for i in windows.indices {
            windows[i].isSelected = windows[i].id == selected
            windows[i].isFocused = windows[i].id == WindowID(pid: 102, number: 2)
        }
        let focused = windows.firstIndex { $0.isSelected }
        return Scene(screen: screen, desk: desk, camera: overviewCamera, transition: 1, windows: windows, look: look,
                     minimap: minimap(windows, camera: overviewCamera, focused: focused), time: 0.2)
    }

    /// The canvas windows with those that don't match `query` dimmed, as a search leaves them.
    static func searchWindows(_ query: String) -> [SceneWindow] {
        canvasWindows.map { w in
            var w = w
            w.dim = w.title.localizedCaseInsensitiveContains(query) ? 0 : 1
            return w
        }
    }

    /// A deep blue-violet desktop picture with soft light, so parallax and
    /// blur are visible.
    static let wallpaper: CGImage = {
        let w = 3024, h = 1964
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let base = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.06, green: 0.09, blue: 0.2, alpha: 1),
                                                           CGColor(red: 0.2, green: 0.08, blue: 0.24, alpha: 1)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(base, start: .zero, end: CGPoint(x: w, y: h), options: [])
        for (x, y, r, c) in [(0.25, 0.7, 0.45, CGColor(red: 0.95, green: 0.45, blue: 0.25, alpha: 0.55)),
                             (0.8, 0.3, 0.5, CGColor(red: 0.3, green: 0.5, blue: 1, alpha: 0.5)),
                             (0.55, 0.9, 0.3, CGColor(red: 0.9, green: 0.3, blue: 0.6, alpha: 0.4))] {
            let glow = CGGradient(colorsSpace: space, colors: [c, c.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
            let center = CGPoint(x: Double(w) * x, y: Double(h) * y)
            ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: Double(w) * r, options: [])
        }
        return ctx.makeImage()!
    }()
}
