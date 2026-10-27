import CoreGraphics
@testable import MielCore
import Testing

// Where the overview camera goes: what "centered" means for each move.
// Everything is checked as drawn, through the lens, in the free area the
// search field and the key hints leave on the active screen.

extension CanvasState {
    /// `rect` as drawn on the active screen at the camera's target.
    func drawn(_ rect: CGRect) -> CGRect { lensedBounds(rect, camera: animator.target, on: activeScreen) }
    var freeArea: CGRect { overviewFreeArea(on: activeScreen) }

    /// The free area minus the room for the workspace pill above and a window's name below.
    var workspaceArea: CGRect { freeArea.insetBy(dx: 0, dy: Self.labelRoom) }
}

func expectCentered(_ r: CGRect, in area: CGRect, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(area.insetBy(dx: -0.5, dy: -0.5).contains(r), "\(r) leaves \(area)", sourceLocation: sourceLocation)
    #expect(abs(r.midX - area.midX) < 0.5 && abs(r.midY - area.midY) < 0.5, "\(r) is off the middle of \(area)",
            sourceLocation: sourceLocation)
}

/// Three tiles on workspace 1 and two on workspace 2; workspace 1 current.
func twoWorkspaces() -> CanvasState {
    var s = tilingState([snapshot(1, onBuiltIn), snapshot(2, onBuiltIn), snapshot(3, onBuiltIn)])
    _ = s.send(.system(.windowFocused(wid(3))))
    _ = s.send(.action(.moveToWorkspace(2)))
    _ = s.send(.system(.windowAppeared(snapshot(4, onBuiltIn))))
    _ = s.send(.action(.workspace(1)))
    _ = s.send(.system(.windowFocused(wid(1))))
    return s
}

@Test func openingCentersTheCurrentWorkspaceBelowTheSearchField() {
    var s = twoWorkspaces()
    _ = s.send(.action(.toggleOverview))
    let area = s.freeArea
    #expect(area.minY > PaletteMetrics.top(s.look, screenHeight: 982, topInset: 38) + s.look.searchHeight) // below the field
    #expect(area.maxY < 982 - 30) // above the key hints
    expectCentered(s.drawn(s.workspaceFrame(1)), in: s.workspaceArea)
    #expect(s.animator.target.zoom <= s.settings.initialZoom + 1e-9)
    // The whole workspace fits: the zoom is the largest that does, or the setting.
    let wider = s.camera(fitting: s.workspaceFrame(1), in: s.workspaceArea, maxZoom: s.animator.target.zoom * 1.01)
    #expect(abs(wider.zoom - s.animator.target.zoom) < 1e-3)
}

@Test func openingWithASmallZoomSettingKeepsIt() {
    var settings = testSettings(layout: .tiles)
    settings.initialZoom = 0.3
    var s = tilingState([snapshot(1, onBuiltIn)], settings: settings)
    _ = s.send(.action(.toggleOverview))
    #expect(abs(s.animator.target.zoom - 0.3) < 1e-9)
    expectCentered(s.drawn(s.workspaceFrame(1)), in: s.workspaceArea)
}

@Test func openingFromAStackCentersItsWorkspace() {
    var s = twoTiles()
    _ = s.send(.action(.layoutStack))
    _ = s.send(.action(.toggleOverview))
    expectCentered(s.drawn(s.workspaceFrame(1)), in: s.workspaceArea)
}

@Test func openingFromFloatingCentersWhatTheScreenShowed() {
    var s = makeState([snapshot(1, onBuiltIn), snapshot(2, onExternal)]) // floating, the camera rests on no workspace
    _ = s.send(.action(.pan(.down)))
    let view = s.deskCamera.toCanvas(builtIn.frame, deskCenter: s.deskCenter)
    _ = s.send(.action(.toggleOverview))
    expectCentered(s.drawn(view), in: s.freeArea)
}

@Test func withoutTheSearchPaletteTheWholeScreenIsFree() {
    var settings = testSettings(layout: .tiles)
    settings.navigatorEnabled = false
    var s = tilingState([snapshot(1, onBuiltIn)], settings: settings)
    _ = s.send(.action(.toggleOverview))
    #expect(s.freeArea == builtIn.frame.size.rect.insetBy(dx: 32, dy: 32))
    expectCentered(s.drawn(s.workspaceFrame(1)), in: s.workspaceArea)
}

@Test func helpOpensOnTheSameView() {
    var a = twoWorkspaces(), b = twoWorkspaces()
    _ = a.send(.action(.toggleOverview))
    _ = b.send(.action(.help))
    #expect(a.animator.target == b.animator.target)
}

@Test func togglingBackLandsExactlyWhereItStarted() {
    for var s in [twoWorkspaces(), makeState([snapshot(1, onBuiltIn)])] {
        let camera = s.deskCamera
        _ = s.send(.action(.toggleOverview))
        #expect(moves(s.send(.action(.toggleOverview))).isEmpty)
        #expect(s.deskCamera == camera && s.animator.target == camera)
    }
}

@Test func selectionWithinTheWorkspaceInViewKeepsTheCamera() {
    var s = twoWorkspaces()
    _ = s.send(.action(.toggleOverview))
    let opened = s.animator.target
    #expect(s.selection == wid(1))
    _ = s.send(.key(.arrow(.right), []))
    #expect(s.selection == wid(2) && s.animator.target == opened)
    _ = s.send(.key(.arrow(.left), []))
    #expect(s.selection == wid(1) && s.animator.target == opened)
    _ = s.send(.select(wid(2))) // hover never moves the camera
    #expect(s.selection == wid(2) && s.animator.target == opened)
}

@Test func selectionInAnotherWorkspaceGlidesThereAndCentersIt() {
    var s = twoWorkspaces()
    _ = s.send(.action(.toggleOverview))
    let zoom = s.animator.target.zoom
    _ = s.send(.text("Ghostty 4"))
    #expect(s.selection == wid(4))
    #expect(abs(s.animator.target.zoom - zoom) < 1e-9) // a glide, not a zoom
    #expect(s.freeArea.contains(s.drawn(s.window(wid(4))!.frame)))
    _ = s.send(.key(.escape, [])) // clears the query; the list goes, so the free area grows again
    _ = s.send(.action(.workspace(2)))
    expectCentered(s.drawn(s.workspaceFrame(2)), in: s.workspaceArea)
    _ = s.send(.action(.workspace(1)))
    expectCentered(s.drawn(s.workspaceFrame(1)), in: s.workspaceArea)
}

@Test func landingEndsExactlyOnTheWorkspace() {
    var s = twoWorkspaces()
    _ = s.send(.action(.toggleOverview))
    _ = s.send(.text("Ghostty 4"))
    _ = s.send(.key(.enter, []))
    #expect(!s.isOverview && s.deskCamera == s.animator.target)
    #expect(s.restingSlot(s.deskCamera)?.slot == 2)
    // Its tiles sit exactly on the screen: the canvas frame is the real frame.
    let w = s.window(wid(4))!
    #expect(s.deskCamera.toDesk(w.frame, deskCenter: s.deskCenter) == s.desiredFrame(w).frame)
}

@Test func fitAllAndFrameStayInTheFreeArea() {
    var s = makeState([snapshot(1, onBuiltIn), snapshot(2, onExternal), snapshot(3, CGRect(x: -900, y: 1500, width: 700, height: 500))])
    _ = s.send(.action(.toggleOverview))
    _ = s.send(.key(.digit(0), .control))
    let all = s.windows.map(\.frame).reduce(CGRect.null) { $0.union($1) }
    expectCentered(s.drawn(all), in: s.freeArea)
    _ = s.send(.select(wid(3)))
    _ = s.send(.key(.character("f"), .control))
    #expect(s.animator.target.zoom <= 1)
    expectCentered(s.drawn(s.window(wid(3))!.frame), in: s.workspaceArea)
}

@Test func theResultListShrinksTheFreeArea() {
    var s = twoWorkspaces()
    _ = s.send(.action(.toggleOverview))
    let field = s.freeArea
    _ = s.send(.key(.tab, []))
    #expect(s.overview.listVisible)
    #expect(s.freeArea.minY > field.minY + 100 && s.freeArea.maxY == field.maxY)
}

@Test func freeAreaIsOnTheActiveScreen() {
    var s = twoWorkspaces()
    s.activeScreenID = external.id
    _ = s.send(.action(.toggleOverview))
    #expect(s.freeArea.maxX <= external.frame.width && s.freeArea.maxY <= external.frame.height)
    // External: no menu bar inset, so the field sits at the plain fraction of its height.
    #expect(abs(s.freeArea.minY - (1080 * s.look.paletteTop + s.look.searchHeight + 32)) < 1e-9)
}

private extension CGSize {
    var rect: CGRect { CGRect(origin: .zero, size: self) }
}

@Test func aSavedLayoutOnAnOddHeightDeskStillRestsOnItsWorkspace() {
    let tall = ScreenInfo(id: 7, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
                          visibleFrame: CGRect(x: 0, y: 38, width: 1800, height: 1131), scale: 2, safeAreaTop: 38, isBuiltIn: true)
    let desk = deskRect([tall])
    let saved = LayoutSnapshot(camera: Camera(center: desk.center), deskCenter: desk.center, windows: [])
    let s = CanvasState(screens: [tall], settings: testSettings(layout: .tiles), ownPID: 1, now: 0, savedLayout: saved)
    #expect(s.deskCamera.center == desk.center) // not rounded off the half point
    #expect(s.slots.origin == .zero && s.restingSlot(s.deskCamera)?.slot == 1)
}

@Test func reduceMotionCutsInsteadOfFlying() {
    var s = makeState([snapshot(1, onBuiltIn)], settings: testSettings(animated: true))
    s.accessibility = AccessibilityOptions(reduceMotion: true, reduceTransparency: true)
    #expect(s.look.reduceMotion && s.look.reduceTransparency && !s.look.increaseContrast)
    _ = s.send(.action(.toggleOverview))
    #expect(s.animator.isSettled && s.transition == 1 && s.camera == s.animator.target) // there at once, lens and all
    s.accessibility = AccessibilityOptions()
    _ = s.send(.action(.toggleOverview))
    #expect(!s.animator.isSettled) // flies again
}

@Test func workspaceKeysWhileSearchingPickOnlyAMatch() {
    var s = twoWorkspaces()
    _ = s.send(.action(.toggleOverview))
    _ = s.send(.text("Ghostty 1"))
    #expect(s.selection == wid(1))
    _ = s.send(.action(.workspace(2))) // no match there: the selection stays with the list
    #expect(s.selection == wid(1) && s.overview.selectedWindow == wid(1))
    expectCentered(s.drawn(s.workspaceFrame(2)), in: s.freeArea.insetBy(dx: 0, dy: CanvasState.labelRoom))
}
