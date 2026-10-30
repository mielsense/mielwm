import CoreGraphics
@testable import MielCore
import Testing

// How Core follows what macOS does to windows: focus after a window goes,
// frame reports that are not the user's, and windows that fight back.

let safari = wid(2, pid: 200)

/// Windows 1 and 2 (Safari's) tiled on workspace 1, window 3 on workspace 2; the camera on 1, Safari focused.
func oneEachOnTwoWorkspaces() -> CanvasState {
    var s = tilingState([snapshot(1, onBuiltIn), snapshot(2, onBuiltIn, app: "Safari", bundle: "com.apple.Safari", pid: 200)])
    _ = s.send(.action(.workspace(2)))
    _ = s.send(.system(.windowAppeared(snapshot(3, onBuiltIn))))
    _ = s.send(.action(.workspace(1)))
    _ = s.advance(1) // past the focus the workspace key asked for
    _ = s.send(.system(.windowFocused(safari)))
    return s
}

// MARK: Focus after the focused window goes

@Test(arguments: ["close", "minimize", "hide"])
func losingTheFocusedWindowKeepsTheWorkspace(_ how: String) {
    var s = oneEachOnTwoWorkspaces()
    let camera = s.deskCamera
    let event: SystemEvent = switch how {
    case "close": .windowClosed(safari)
    case "minimize": .windowMinimized(safari, true)
    default: .appHidden(pid: 200, true)
    }
    #expect(focuses(s.send(.system(event))) == [wid(1)])
    // macOS hands focus to a window of its choosing, here one on workspace 2.
    _ = s.send(.system(.windowFocused(wid(3))))
    #expect(s.currentWorkspace == 1)
    #expect(s.deskCamera == camera)
}

@Test func closingTheLastWindowOfAWorkspaceKeepsTheCamera() {
    var s = tilingState([snapshot(1, onBuiltIn)])
    _ = s.send(.action(.workspace(2)))
    _ = s.send(.system(.windowAppeared(snapshot(3, onBuiltIn))))
    _ = s.advance(1)
    _ = s.send(.system(.windowFocused(wid(3))))
    let camera = s.deskCamera
    #expect(focuses(s.send(.system(.windowClosed(wid(3))))).isEmpty)
    _ = s.send(.system(.windowFocused(wid(1)))) // parked on workspace 1
    #expect(s.currentWorkspace == 2)
    #expect(s.deskCamera == camera)
    _ = s.advance(1)
    _ = s.send(.system(.windowFocused(wid(1)))) // later focus is the user's again
    #expect(s.currentWorkspace == 1)
}

// MARK: Reports nobody dragged

@Test func appResizingItselfSnapsBackWithoutMovingTheSplit() {
    var s = twoTiles()
    // An Electron app restores its saved bounds: wider, with no mouse button down.
    let commands = s.send(.system(.windowFrameChanged(wid(1), CGRect(x: 12, y: 50, width: 840, height: 850))))
    #expect(moves(commands) == [wid(1): left])
    #expect(s.canvasFrame(1) == left && s.canvasFrame(2) == right)
}
