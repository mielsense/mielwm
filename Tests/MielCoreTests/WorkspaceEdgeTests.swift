@testable import MielCore
import Testing

// Focus and move stop at the workspace's edge, as AeroSpace's do, unless set to cross.

/// Windows 1 and 2 opened at startup, so each has a workspace of its own (1 and 2).
private func oneWindowEach(cross: Bool = false) -> CanvasState {
    var settings = testSettings(layout: .tiles)
    settings.crossWorkspaces = cross
    var s = makeState([snapshot(1, onBuiltIn), snapshot(2, onBuiltIn)], settings: settings)
    _ = s.send(.system(.windowFocused(wid(1))))
    return s
}

@Test func focusStopsAtTheWorkspaceEdge() {
    var s = oneWindowEach()
    #expect(s.send(.action(.focus(.right))).isEmpty)
    #expect(s.focused == wid(1) && s.currentWorkspace == 1)
    s = oneWindowEach(cross: true)
    _ = s.send(.action(.focus(.right)))
    #expect(s.focused == wid(2) && s.currentWorkspace == 2)
}

@Test func focusStillReachesPinnedWindowsAndOnesOffEveryWorkspace() {
    var s = tilingState([snapshot(1, onBuiltIn), snapshot(2, onExternal, app: "Calculator", bundle: "com.apple.calculator")])
    _ = s.send(.system(.windowFocused(wid(1))))
    _ = s.send(.action(.focus(.right))) // the floating window on the other display belongs to no workspace
    #expect(s.focused == wid(2))
}

@Test func focusInsideAWorkspaceAndInTheOverviewStillMoves() {
    var s = twoTiles()
    _ = s.send(.action(.focus(.right)))
    #expect(s.focused == wid(2))
    s = oneWindowEach()
    _ = s.send(.action(.toggleOverview))
    _ = s.send(.action(.focus(.right))) // zoomed out, the arrows roam the whole canvas
    #expect(s.selection == wid(2))
}

@Test func moveStopsAtTheWorkspaceEdge() {
    var s = twoTiles()
    _ = s.send(.action(.nudge(.right)))
    _ = s.send(.action(.nudge(.right))) // past the end: nothing
    #expect(s.members(1) == [2, 1] && s.members(2) == nil && s.currentWorkspace == 1)
}
