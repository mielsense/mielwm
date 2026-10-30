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

// MARK: Slots on displays of different widths

let studio = ScreenInfo(id: 3, name: "Studio Display", frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                        visibleFrame: CGRect(x: 0, y: 25, width: 2560, height: 1415), scale: 2)
let laptop = ScreenInfo(id: 4, name: "Built-in Retina Display", frame: CGRect(x: 2560, y: 0, width: 1512, height: 982),
                        visibleFrame: CGRect(x: 2560, y: 38, width: 1512, height: 874), scale: 2, isBuiltIn: true)

@Test(arguments: [studio.id, laptop.id])
func noDisplayShowsANeighbouringWorkspace(_ shownOn: UInt32) {
    var s = CanvasState(screens: [studio, laptop], settings: testSettings(layout: .tiles), ownPID: 1, now: 0)
    _ = s.send(.tick(20))
    for n in [1, 3] { // the neighbours lay out for the wide display
        s.activeScreenID = studio.id
        _ = s.send(.action(.workspace(n)))
        _ = s.send(.system(.windowAppeared(snapshot(UInt32(n), CGRect(x: 100, y: 100, width: 800, height: 600)))))
    }
    s.activeScreenID = shownOn
    _ = s.send(.action(.workspace(2)))
    for n in [1, 3] {
        let neighbour = s.deskCamera.toDesk(s.workspaceFrame(n), deskCenter: s.deskCenter)
        #expect(s.screens.allSatisfy { !$0.frame.intersects(neighbour) }, "workspace \(n) shows")
    }
}

/// Workspace 3 current with a tile and a floating window, on the built-in display alone.
func builtInAloneOnWorkspace3() -> CanvasState {
    var s = CanvasState(screens: [builtIn], settings: testSettings(layout: .tiles), ownPID: 1, now: 0)
    s.activeScreenID = builtIn.id
    _ = s.send(.tick(20))
    _ = s.send(.action(.workspace(3)))
    _ = s.send(.system(.windowAppeared(snapshot(1, onBuiltIn))))
    _ = s.send(.system(.windowAppeared(snapshot(2, onBuiltIn, app: "Calculator", bundle: "com.apple.calculator"))))
    return s
}

@Test func pluggingInADisplaySpreadsTheSlotsAndKeepsTheWorkspace() throws {
    var s = builtInAloneOnWorkspace3()
    let floating = try #require(s.canvasFrame(2)).offsetBy(dx: -s.slots.origin(3).x, dy: 0)
    _ = s.send(.system(.screensChanged([builtIn, external])))
    #expect(s.slots.step == 3672) // the desk, 3432, plus the gap
    #expect(s.restingSlot(s.deskCamera)?.slot == 3)
    #expect(s.canvasFrame(2)?.offsetBy(dx: -s.slots.origin(3).x, dy: 0) == floating) // same place in its slot
    _ = s.advance(2)
    #expect(s.currentWorkspace == 3 && s.window(wid(1))?.parked == false && s.window(wid(2))?.parked == false)
}

@Test func aLayoutSavedOnNarrowerDisplaysSpreadsTheSlots() throws {
    let old = builtInAloneOnWorkspace3()
    let floating = try #require(old.canvasFrame(2)).offsetBy(dx: -old.slots.origin(3).x, dy: 0)
    var s = makeState([snapshot(1, onBuiltIn), snapshot(2, onBuiltIn, app: "Calculator", bundle: "com.apple.calculator")],
                      settings: testSettings(layout: .tiles), saved: LayoutSnapshot(old))
    #expect(s.slots.step == 3672)
    #expect(s.restingSlot(s.deskCamera)?.slot == 3 && s.currentWorkspace == 3)
    #expect(s.window(wid(1))?.workspace == 3)
    #expect(s.canvasFrame(2)?.offsetBy(dx: -s.slots.origin(3).x, dy: 0) == floating)
    _ = s.advance(1)
}

// MARK: Windows that fight back

@Test func tileSnapBacksStartOverAfterAQuietSpell() {
    var s = twoTiles()
    let moved = left.offsetBy(dx: 30, dy: 30)
    for _ in 0 ..< 2 {
        #expect(moves(s.send(.system(.windowFrameChanged(wid(1), moved)))) == [wid(1): left])
        _ = s.send(.system(.windowFrameChanged(wid(1), left)))
    }
    #expect(s.send(.system(.windowFrameChanged(wid(1), moved))).isEmpty) // the third in a row: let it be
    _ = s.advance(4)
    // Seconds later it is a new move, and it snaps back again.
    #expect(moves(s.send(.system(.windowFrameChanged(wid(1), moved.offsetBy(dx: 10, dy: 0))))) == [wid(1): left])
}

// MARK: Late reports

@Test func aLateReportOfAnEarlierMoveIsNotAdopted() throws {
    var s = focusedState()
    let slot = try #require(moves(panDesk(&s, dx: -3000))[wid(1)])
    #expect(moves(panDesk(&s, dx: 3000))[wid(1)] == onBuiltIn) // back before the park landed
    _ = s.advance(1.5)
    // The busy app reports the park only now, after both moves lapsed.
    #expect(s.send(.system(.windowFrameChanged(wid(1), slot))).isEmpty)
    #expect(s.canvasFrame(1) == onBuiltIn)
    _ = s.send(.system(.windowFrameChanged(wid(1), onBuiltIn)))
    // A move nobody asked for is still the user's.
    let dragged = onBuiltIn.offsetBy(dx: 200, dy: 0)
    _ = s.send(.system(.windowFrameChanged(wid(1), dragged)))
    #expect(s.canvasFrame(1) == dragged)
}

@Test func aTileThatGaveInStaysGivenInThroughStrayReports() {
    var s = twoTiles()
    let refused = CGRect(x: 12, y: 50, width: 740, height: 700) // a maximum height, say
    var n = 0, commands = s.send(.system(.windowFrameChanged(wid(1), refused)))
    while n < 8, moves(commands)[wid(1)] != nil {
        n += 1
        // The app answers each tile we send with its own height, then repeats it (Electron's stray moves).
        _ = s.send(.system(.windowFrameChanged(wid(1), refused)))
        commands = s.advance(1.5) + s.send(.system(.windowFrameChanged(wid(1), refused)))
    }
    #expect(n <= Int(CanvasState.maxReparks))
    #expect(s.canvasFrame(1)?.size == refused.size)
}

@Test func aMoveThatNeverShowsUpIsSentOnceMore() {
    var s = focusedState()
    let asked = moves(s.send(.action(.nudge(.right))))[wid(1)]
    #expect(asked != nil)
    #expect(moves(s.advance(1.5))[wid(1)] == asked) // no report at all: the app missed it
    #expect(s.advance(1.5).isEmpty) // only once
}
