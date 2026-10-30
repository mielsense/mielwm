import Foundation
import MielCore

// Made-up windows and workspaces for snapshot and the previews: nothing real is read or moved.

/// Three workspace frames for `--workspaces`: the screen's own (current),
/// one to its right and one below, as the tiling layout would place them.
func syntheticWorkspaces(_ screen: ScreenInfo) -> [SceneWorkspace] {
    let v = screen.visibleFrame.insetBy(dx: 8, dy: 8)
    return [
        SceneWorkspace(number: 1, canvasFrame: v, mode: .tiles, isCurrent: true),
        SceneWorkspace(number: 2, canvasFrame: v.offsetBy(dx: v.width + 160, dy: 0), mode: .stack),
        SceneWorkspace(number: 3, canvasFrame: v.offsetBy(dx: 0, dy: v.height + 160), mode: .tiles),
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
