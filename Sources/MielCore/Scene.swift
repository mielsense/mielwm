import CoreGraphics
import Foundation

public extension CanvasState {
    /// Everything one overlay draws this frame.
    func scene(for screen: ScreenInfo, time: Double? = nil) -> Scene {
        let look = self.look
        let matches = isOverview ? overview.matchSet : nil
        let sceneWindows = drawnWindows.map { w, frame in
            SceneWindow(id: w.id, canvasFrame: frame, title: w.displayTitle, appName: w.appName, bundleID: w.bundleID,
                        dim: matches.map { $0.contains(w.id) ? 0 : look.dimUnmatched } ?? 0,
                        isSelected: isOverview && w.id == selection && (matches?.contains(w.id) ?? true), isFocused: w.id == focused, isPinned: w.pinned != nil)
        }
        let minimap = look.minimapEnabled && animator.transition > 0.001 ? minimapModel(for: screen) : nil
        var scene = Scene(screen: screen, desk: deskRect(screens), camera: camera, transition: animator.transition,
                          windows: sceneWindows, look: look, minimap: minimap, hud: hud(for: screen),
                          dropIndicator: dropIndicator, time: time ?? now)
        scene.searching = scene.hud.mode == .search && !scene.hud.query.isEmpty
        scene.workspaces = workspaces.map {
            var ws = SceneWorkspace(number: $0.number, canvasFrame: workspaceFrame($0.slot), mode: $0.mode,
                                    isCurrent: $0.slot == currentWorkspace)
            if $0.members.isEmpty { ws.emptyMessage = emptyMessage($0.slot) }
            return ws
        }
        return scene
    }

    /// The shown windows back to front, where the overview draws them
    /// (pinned ones at their desk frames). Zoomed out, a stack reads as a
    /// deck of cards: each window behind peeks out above the one in front, a
    /// little narrower, up to three deep; the selected member comes to the
    /// front, so browsing a stack shows each window.
    internal var drawnWindows: [(window: ManagedWindow, frame: CGRect)] {
        let shown = windows.filter(\.isShown)
        var ordered = shown.filter { $0.pinned == nil } + shown.filter { $0.pinned != nil } // pinned on top
        var fan: [WindowID: CGRect] = [:]
        for ws in workspaces where ws.mode == .stack {
            let members = Set(ws.members)
            let spots = ordered.indices.filter { members.contains(ordered[$0].id) && ordered[$0].pinned == nil }
            var stacked = spots.map { ordered[$0] }
            if isOverview, let s = selection, let i = stacked.firstIndex(where: { $0.id == s }) { stacked.append(stacked.remove(at: i)) }
            for (spot, w) in zip(spots, stacked) { ordered[spot] = w } // the same places in the z-order, the selection last
            for (depth, w) in stacked.reversed().enumerated() {
                let d = CGFloat(min(depth, 3)) * animator.transition
                fan[w.id] = w.frame.insetBy(dx: 24 * d, dy: 0).offsetBy(dx: 0, dy: -14 * d)
            }
        }
        return ordered.map { ($0, $0.pinned ?? fan[$0.id] ?? $0.frame) }
    }

    /// "Workspace 4 is empty", with the live chord that moves a window there.
    func emptyMessage(_ slot: Int) -> String {
        let name = slot <= 9 ? "Workspace \(slot) is empty" : "This workspace is empty"
        let chords = settings.chords.filter { $0.value == .moveToWorkspace(slot) }.map(\.key.symbol)
        guard let chord = chords.min(by: { ($0.count, $0) < ($1.count, $1) }) else { return name }
        return name + "  {\(chord)} Move a window here"
    }

    /// The minimap's contents for one screen: canvas frames, matches dimmed,
    /// and the canvas rect that screen shows.
    func minimapModel(for screen: ScreenInfo) -> MinimapModel {
        let matches = isOverview ? overview.matchSet : nil
        let shown = candidates
        let marked = selection ?? focused
        var model = MinimapModel(windows: shown.map { w in (w.frame, matches.map { $0.contains(w.id) ? 0 : 0.78 } ?? 0) },
                                 focusedIndex: shown.firstIndex { $0.id == marked },
                                 viewport: camera.toCanvas(screen.frame, deskCenter: deskCenter))
        model.showsArrangeButton = isOverview
        model.workspaces = workspaces.map { workspaceFrame($0.slot) }
        return model
    }

    /// The minimap's layout on one screen, for hit testing a click.
    func minimapLayout(for screen: ScreenInfo) -> MinimapLayout {
        let m = minimapModel(for: screen)
        return MielCore.minimapLayout(screenSize: screen.frame.size, look: look, windows: m.windows.map(\.frame), viewport: m.viewport,
                                           workspaces: m.workspaces)
    }

    /// The canvas point under a screen-local point, through the lens.
    func canvasPoint(atScreenPoint p: CGPoint, on screen: ScreenInfo) -> CGPoint {
        camera.toCanvas(deskPoint(atScreenPoint: p, on: screen), deskCenter: deskCenter)
    }

    /// The desk point the lens shows at a screen-local point.
    func deskPoint(atScreenPoint p: CGPoint, on screen: ScreenInfo) -> CGPoint {
        let source = lensSourcePoint(p, screenSize: screen.frame.size, look: look, transition: animator.transition)
        return CGPoint(x: source.x + screen.frame.minX, y: source.y + screen.frame.minY)
    }

    /// The frontmost window under a screen-local point, as drawn: pinned
    /// windows at their desk frames, stacks fanned out.
    func window(atScreenPoint p: CGPoint, on screen: ScreenInfo) -> WindowID? {
        let desk = deskPoint(atScreenPoint: p, on: screen), c = camera.toCanvas(desk, deskCenter: deskCenter)
        return drawnWindows.last { $0.frame.contains($0.window.pinned == nil ? c : desk) }?.window.id
    }
}
