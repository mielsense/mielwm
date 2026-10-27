import CoreGraphics
@testable import MielCore
import Testing

// Rules (a)-(h) of the reducer, against the user's two-display desk.

let onBuiltIn = CGRect(x: 100, y: 100, width: 800, height: 600)

/// One window, focused, at `onBuiltIn`.
func focusedState(_ frame: CGRect = onBuiltIn) -> CanvasState {
    var s = makeState([snapshot(1, frame)])
    _ = s.send(.system(.windowFocused(wid(1))))
    return s
}

/// Pans the full-size canvas by `dx` desk points and lets go.
func panDesk(_ s: inout CanvasState, dx: CGFloat) -> [WindowCommand] {
    s.run(.gesture(.pan(CGVector(dx: dx, dy: 0))), .gesture(.panEnded(velocity: .zero)))
}

@Test func appearingWindowStaysWhereItIs() {
    var s = CanvasState(screens: [builtIn, external], settings: testSettings(), ownPID: 1)
    let commands = s.send(.system(.windowAppeared(snapshot(1, onBuiltIn))))
    #expect(commands.isEmpty)
    #expect(s.canvasFrame(1) == onBuiltIn)
}

@Test func ownMoveIgnoredAcrossSizePositionSizeReports() {
    var s = focusedState()
    let commands = s.send(.action(.grow))
    let target = CGRect(x: 60, y: 60, width: 880, height: 680)
    #expect(moves(commands)[wid(1)] == target)
    // System applies size, position, size: three reports, the first one off.
    #expect(s.send(.system(.windowFrameChanged(wid(1), CGRect(x: 100, y: 100, width: 880, height: 680)))).isEmpty)
    #expect(s.canvasFrame(1) == target) // the intermediate report is not adopted
    #expect(s.send(.system(.windowFrameChanged(wid(1), target))).isEmpty)
    #expect(s.send(.system(.windowFrameChanged(wid(1), target))).isEmpty)
    #expect(s.advance(2).isEmpty)
    #expect(s.canvasFrame(1) == target)
}

@Test func userDragAdopted() {
    var s = focusedState()
    let dragged = CGRect(x: 300, y: 200, width: 800, height: 600)
    let commands = s.send(.system(.windowFrameChanged(wid(1), dragged)))
    #expect(commands.isEmpty)
    #expect(s.canvasFrame(1) == dragged)
    // Adopted in canvas space: after a pan it is still where the user put it on the canvas.
    _ = panDesk(&s, dx: -200)
    #expect(s.canvasFrame(1) == dragged)
}

@Test func clampNotAdopted() {
    var s = focusedState()
    _ = s.send(.action(.nudge(.right)))
    let asked = CGRect(x: 180, y: 100, width: 800, height: 600)
    #expect(s.canvasFrame(1) == asked)
    // macOS puts it somewhere else of the same size and never reports what we asked for.
    _ = s.send(.system(.windowFrameChanged(wid(1), CGRect(x: 180, y: 140, width: 800, height: 600))))
    _ = s.advance(1.5)
    #expect(s.canvasFrame(1) == asked)
}

@Test func onlyLastReportIsJudged() {
    var s = focusedState()
    _ = s.send(.action(.grow))
    // Two reports that never match; the size of the last one is what the app took.
    _ = s.send(.system(.windowFrameChanged(wid(1), CGRect(x: 60, y: 60, width: 700, height: 500))))
    _ = s.send(.system(.windowFrameChanged(wid(1), CGRect(x: 60, y: 60, width: 860, height: 660))))
    _ = s.advance(1.5)
    #expect(s.canvasFrame(1) == CGRect(x: 60, y: 60, width: 860, height: 660))
}

@Test func windowAboveTopEdgeLandsBelowMenuBar() {
    var s = focusedState(CGRect(x: 100, y: 200, width: 800, height: 600))
    _ = s.send(.action(.nudge(.up))) // canvas y 120
    _ = s.send(.action(.nudge(.up))) // canvas y 40
    let commands = s.send(.action(.nudge(.up))) // canvas y -40: above the notch display
    #expect(s.canvasFrame(1)?.minY == -40)
    #expect(moves(commands)[wid(1)]?.minY == builtIn.visibleFrame.minY)
}

@Test func panningOffCameraParksInTheCornerAwayFromTheOtherDisplay() throws {
    var s = focusedState()
    let commands = panDesk(&s, dx: -3000)
    let parked = try #require(moves(commands)[wid(1)])
    // Off the left of the built-in display: its bottom-left corner, 1 point showing.
    #expect(parked == CGRect(x: 1 - 800, y: builtIn.visibleFrame.maxY - 1, width: 800, height: 600))
    #expect(s.window(wid(1))?.parked == true)
    #expect(s.canvasFrame(1) == onBuiltIn)
    #expect(isHiddenFrame(parked, screens: s.screens))
}

@Test func parkedWindowPulledBackIsReparkedTwiceThenAdopted() throws {
    var s = focusedState()
    let slot = try #require(moves(panDesk(&s, dx: -3000))[wid(1)])
    _ = s.send(.system(.windowFrameChanged(wid(1), slot))) // our park confirmed
    let pulled = CGRect(x: 200, y: 200, width: 800, height: 600)
    for _ in 0 ..< 2 {
        let again = s.send(.system(.windowFrameChanged(wid(1), pulled)))
        #expect(moves(again)[wid(1)] == slot)
        _ = s.send(.system(.windowFrameChanged(wid(1), slot)))
    }
    let third = s.send(.system(.windowFrameChanged(wid(1), pulled)))
    #expect(third.isEmpty)
    #expect(s.window(wid(1))?.parked == false)
    #expect(s.window(wid(1)).map { s.deskFrame($0) } == pulled)
}

@Test func repeatedReportsOfTheParkSlotAreNotPullBacks() throws {
    var s = focusedState()
    let slot = try #require(moves(panDesk(&s, dx: -3000))[wid(1)])
    // Size, position, size all report the final frame; Electron apps add stray moves.
    for _ in 0 ..< 4 { #expect(s.send(.system(.windowFrameChanged(wid(1), slot))).isEmpty) }
    #expect(s.canvasFrame(1) == onBuiltIn)
    #expect(s.window(wid(1))?.parked == true)
    // The re-park budget is untouched: a pull-back is still sent back.
    let pulled = CGRect(x: 200, y: 200, width: 800, height: 600)
    #expect(moves(s.send(.system(.windowFrameChanged(wid(1), pulled))))[wid(1)] == slot)
}

@Test func parkedWindowThatResizesKeepsItsSizeAndIsReparked() throws {
    var s = focusedState()
    let slot = try #require(moves(panDesk(&s, dx: -3000))[wid(1)])
    _ = s.send(.system(.windowFrameChanged(wid(1), slot)))
    let grown = CGRect(x: slot.minX, y: slot.minY, width: 1000, height: 700)
    let commands = s.send(.system(.windowFrameChanged(wid(1), grown)))
    #expect(s.canvasFrame(1)?.size == CGSize(width: 1000, height: 700))
    #expect(moves(commands)[wid(1)] == CGRect(x: 1 - 1000, y: slot.minY, width: 1000, height: 700))
    #expect(s.window(wid(1))?.parked == true)
}

@Test func outsideFocusFliesCameraToParkedWindow() throws {
    var s = makeState([snapshot(1, onBuiltIn), snapshot(2, CGRect(x: 1700, y: 200, width: 900, height: 600))])
    _ = s.send(.system(.windowFocused(wid(2))))
    _ = panDesk(&s, dx: 4000) // window 1 off the right edge: parked
    #expect(s.window(wid(1))?.parked == true)
    let commands = s.send(.system(.windowFocused(wid(1)))) // Cmd-Tab to it
    let landed = try #require(moves(commands)[wid(1)])
    #expect(builtIn.visibleFrame.contains(landed))
    #expect(s.window(wid(1))?.parked == false)
    #expect(s.focused == wid(1))
    #expect(focuses(commands).isEmpty) // it already has focus
}

@Test func outsideFocusOfVisibleWindowKeepsCamera() {
    var s = makeState([snapshot(1, onBuiltIn), snapshot(2, CGRect(x: 1700, y: 200, width: 900, height: 600))])
    let camera = s.deskCamera
    #expect(s.send(.system(.windowFocused(wid(2)))).isEmpty)
    #expect(s.deskCamera == camera)
}

@Test func ownProcessFocusIgnored() {
    var s = makeState([snapshot(1, onBuiltIn, pid: 1)])
    _ = panDesk(&s, dx: -3000)
    let camera = s.deskCamera
    #expect(s.send(.system(.windowFocused(WindowID(pid: 1, number: 1)))).isEmpty)
    #expect(s.deskCamera == camera)
    #expect(s.focused == nil)
}

@Test func launchAdoptionPlacesCornerWindowsNearTheCamera() throws {
    var s = makeState([snapshot(1, CGRect(x: 356, y: 175, width: 800, height: 600))])
    // AeroSpace hid this one in the external display's bottom-right corner.
    let hidden = CGRect(x: 3431, y: 1079, width: 700, height: 500)
    let commands = s.send(.system(.windowAppeared(snapshot(2, hidden))))
    let placed = try #require(moves(commands)[wid(2)])
    #expect(!isHiddenFrame(placed, screens: s.screens))
    let canvas = try #require(s.canvasFrame(2))
    let first = try #require(s.canvasFrame(1))
    #expect(!canvas.intersects(first))
    #expect(canvas.distance(to: builtIn.visibleFrame.center) < 1600)
}

@Test func savedLayoutWinsOverLaunchAdoption() throws {
    let far = CGRect(x: 6000, y: 300, width: 700, height: 500)
    let saved = LayoutSnapshot(camera: Camera(center: CGPoint(x: 1716, y: 540)), deskCenter: CGPoint(x: 1716, y: 540), windows: [
        SavedWindow(id: nil, bundleID: "com.mitchellh.ghostty", appName: "Ghostty", title: "notes", ordinal: 0,
                    frame: far, deskFrame: far, parked: true),
    ])
    var s = makeState([], saved: saved)
    let commands = s.send(.system(.windowAppeared(snapshot(2, CGRect(x: 3431, y: 1079, width: 700, height: 500), title: "notes"))))
    #expect(s.canvasFrame(2) == far)
    #expect(s.window(wid(2))?.parked == true)
    // Still in a park slot, now ours: the external display's bottom-right.
    #expect(moves(commands)[wid(2)] == nil)
}

@Test func unparkAllPutsEveryWindowOnScreen() {
    var s = makeState([snapshot(1, onBuiltIn), snapshot(2, CGRect(x: 1700, y: 200, width: 900, height: 600)),
                       snapshot(3, CGRect(x: 300, y: 300, width: 600, height: 400), pid: 200),
                       snapshot(4, CGRect(x: 2000, y: 300, width: 600, height: 400))])
    _ = panDesk(&s, dx: 6000)
    #expect(s.windows.allSatisfy { $0.parked })
    // Parked windows of a hidden app (⌘H) and a minimized parked window come back too.
    _ = s.run(.system(.appHidden(pid: 200, true)), .system(.windowMinimized(wid(4), true)))
    let commands = moves(s.send(.unparkAll))
    #expect(commands.count == 4)
    for frame in commands.values { #expect(!isHiddenFrame(frame, screens: s.screens)) }
    #expect(s.windows.allSatisfy { !$0.parked })
}

@Test func unplugKeepsCanvasFramesAndReplugRestoresPositions() throws {
    let onExternal = CGRect(x: 2000, y: 200, width: 900, height: 600)
    var s = makeState([snapshot(1, onBuiltIn), snapshot(2, onExternal)])

    let unplug = moves(s.send(.system(.screensChanged([builtIn]))))
    let parked = try #require(unplug[wid(2)])
    #expect(isHiddenFrame(parked, screens: [builtIn]))
    // macOS shuffles windows onto the remaining display; ignored during the grace period.
    _ = s.send(.system(.windowFrameChanged(wid(2), CGRect(x: 300, y: 100, width: 900, height: 600))))
    _ = s.advance(2)
    #expect(s.canvasFrame(1) == onBuiltIn)
    #expect(s.canvasFrame(2) == onExternal)

    let replug = s.run(.system(.screensChanged([builtIn, external]))) + s.advance(2)
    #expect(moves(replug)[wid(2)] == onExternal)
    #expect(s.canvasFrame(2) == onExternal)
    #expect(s.window(wid(2))?.parked == false)
}

@Test func windowOnTheSeamMapsAcrossBothDisplays() {
    let seam = CGRect(x: 1300, y: 100, width: 600, height: 400)
    var s = makeState([snapshot(1, seam)])
    #expect(s.canvasFrame(1) == seam)
    #expect(s.window(wid(1))?.parked == false)
    // The pointer finds it from both sides of the seam, through a 2x and a 1x display.
    #expect(s.window(atScreenPoint: CGPoint(x: 1400, y: 200), on: builtIn) == wid(1))
    #expect(s.window(atScreenPoint: CGPoint(x: 100, y: 200), on: external) == wid(1))
    // Zoomed out the overview still draws it as one rect in canvas space.
    _ = s.send(.action(.toggleOverview))
    let scene = s.scene(for: external)
    #expect(scene.windows.first?.canvasFrame == seam)
    #expect(moves(s.send(.action(.toggleOverview))).isEmpty)
}

@Test func closedWindowLeavesMRUAndSelection() {
    var s = makeState([snapshot(1, onBuiltIn), snapshot(2, CGRect(x: 1700, y: 200, width: 900, height: 600))])
    _ = s.run(.system(.windowFocused(wid(1))), .system(.windowFocused(wid(2))))
    _ = s.send(.system(.windowClosed(wid(2))))
    #expect(s.mru.order == [wid(1)])
    #expect(s.focused == nil)
    _ = s.send(.system(.appTerminated(pid: 100)))
    #expect(s.windows.isEmpty)
}

@Test func nonStandardWindowsStayUnmanaged() {
    var s = CanvasState(screens: [builtIn], settings: testSettings(), ownPID: 1)
    var sheet = snapshot(1, onBuiltIn)
    sheet.isStandard = false
    _ = s.send(.system(.windowAppeared(sheet)))
    #expect(s.windows.isEmpty)
}

@Test func autoPlaceOffLeavesCornerWindowsAlone() {
    var settings = testSettings()
    settings.autoPlace = false
    var s = makeState([], settings: settings)
    let hidden = CGRect(x: 3431, y: 1079, width: 700, height: 500)
    #expect(s.send(.system(.windowAppeared(snapshot(2, hidden)))).isEmpty)
    #expect(s.canvasFrame(2) == hidden)
}
