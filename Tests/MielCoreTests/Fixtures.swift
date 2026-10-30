import CoreGraphics
@testable import MielCore

// The user's desk: the built-in notch display (2x) with an external 1080p
// display (1x) to its right. Global points, y down.
let builtIn = ScreenInfo(id: 1, name: "Built-in Retina Display", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                         visibleFrame: CGRect(x: 0, y: 38, width: 1512, height: 874), scale: 2, safeAreaTop: 38, isBuiltIn: true)
let external = ScreenInfo(id: 2, name: "DELL U2419H", frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
                          visibleFrame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), scale: 1)

func wid(_ n: UInt32, pid: Int32 = 100) -> WindowID { WindowID(pid: pid, number: n) }

func snapshot(_ n: UInt32, _ frame: CGRect, title: String? = nil, app: String = "Ghostty",
              bundle: String = "com.mitchellh.ghostty", pid: Int32 = 100) -> WindowSnapshot {
    WindowSnapshot(id: wid(n, pid: pid), bundleID: bundle, appName: app, title: title ?? "\(app) \(n)", frame: frame)
}

/// Animations off unless asked for, so the camera is where it is going.
/// New windows float, as before workspaces, so these tests keep their intent; workspace tests ask for `layout`.
func testSettings(animated: Bool = false, layout: LayoutMode = .floating) -> Settings {
    var s = Settings()
    s.animationEnabled = animated
    s.defaultLayout = layout
    return s
}

func makeState(_ windows: [WindowSnapshot], screens: [ScreenInfo] = [builtIn, external],
               settings: Settings = testSettings(), saved: LayoutSnapshot? = nil) -> CanvasState {
    var s = CanvasState(screens: screens, settings: settings, ownPID: 1, now: 0, savedLayout: saved)
    s.activeScreenID = screens.first?.id
    for w in windows { _ = s.send(.system(.windowAppeared(w))) }
    return s
}

extension CanvasState {
    /// Sends inputs in order and returns every command they caused.
    mutating func run(_ inputs: CoreInput...) -> [WindowCommand] {
        inputs.flatMap { send($0) }
    }

    /// Ticks forward by `seconds` in 1/120 s frames.
    mutating func advance(_ seconds: Double) -> [WindowCommand] {
        var out: [WindowCommand] = []
        let end = now + seconds
        while now < end - 1e-9 { out += send(.tick(min(end, now + 1.0 / 120))) }
        return out
    }

    /// Every window reports the frame it was last sent, as an obliging app does.
    mutating func confirmMoves() {
        for w in windows { _ = send(.system(.windowFrameChanged(w.id, w.frame))) }
    }

    func canvasFrame(_ n: UInt32) -> CGRect? { window(wid(n))?.frame }
}

func moves(_ commands: [WindowCommand]) -> [WindowID: CGRect] {
    var out: [WindowID: CGRect] = [:]
    for case let .setFrame(id, frame) in commands { out[id] = frame }
    return out
}

func focuses(_ commands: [WindowCommand]) -> [WindowID] {
    commands.compactMap { if case let .focus(id) = $0 { id } else { nil } }
}
