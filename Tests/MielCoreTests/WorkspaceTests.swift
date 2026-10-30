import CoreGraphics
import Foundation
@testable import MielCore
import Testing

// Workspaces: tiles and stacks on the canvas, on the user's two-display desk.
// Slot 1 is the built-in display's frame on the canvas; slots are 3432 + 240 apart.

let area = CGRect(x: 12, y: 50, width: 1488, height: 850) // the built-in's tile area with the default gaps
let left = CGRect(x: 12, y: 50, width: 740, height: 850), right = CGRect(x: 760, y: 50, width: 740, height: 850)

/// Tiling on, past the startup window, so new windows join the current workspace.
func tilingState(_ windows: [WindowSnapshot] = [], settings: Settings = testSettings(layout: .tiles)) -> CanvasState {
    var s = CanvasState(screens: [builtIn, external], settings: settings, ownPID: 1, now: 0)
    s.activeScreenID = builtIn.id
    _ = s.send(.tick(20))
    for w in windows { _ = s.send(.system(.windowAppeared(w))) }
    return s
}

/// Two tiles on workspace 1, window 1 focused, both moves confirmed.
func twoTiles() -> CanvasState {
    var s = tilingState([snapshot(1, onBuiltIn), snapshot(2, onBuiltIn.offsetBy(dx: 40, dy: 40))])
    _ = s.send(.system(.windowFocused(wid(1))))
    for w in s.windows { _ = s.send(.system(.windowFrameChanged(w.id, w.frame))) }
    return s
}

extension CanvasState {
    func members(_ slot: Int) -> [UInt32]? { workspaces.first { $0.slot == slot }?.members.map(\.number) }
    func mode(_ slot: Int) -> LayoutMode? { workspaces.first { $0.slot == slot }?.mode }
}

// MARK: Tile math

@Test func tilesSplitEvenlyWithWholeEdgesAndExactGaps() {
    #expect(tileFrames(in: area, weights: [1, 1], horizontal: true, gap: 8) == [left, right])
    let three = tileFrames(in: area, weights: [1, 1, 1], horizontal: true, gap: 8)
    #expect(three.map(\.minX) == [12, 511, 1009])
    #expect(three.map(\.width) == [491, 490, 491])
    #expect(three.last?.maxX == area.maxX)
    #expect(zip(three, three.dropFirst()).allSatisfy { $1.minX - $0.maxX == 8 })
    #expect(tileFrames(in: area, weights: [1, 1], horizontal: false, gap: 8)
        == [CGRect(x: 12, y: 50, width: 1488, height: 421), CGRect(x: 12, y: 479, width: 1488, height: 421)])
    #expect(tileFrames(in: area, weights: [], horizontal: true, gap: 8).isEmpty)
    #expect(tileFrames(in: area, weights: [1], horizontal: true, gap: 8) == [area])
}

@Test func tilesFollowWeightsButKeepAMinimum() {
    let weighted = tileFrames(in: area, weights: [2, 1], horizontal: true, gap: 8)
    #expect(weighted.map(\.width) == [987, 493])
    let squeezed = tileFrames(in: area, weights: [20, 1], horizontal: true, gap: 8)
    #expect(squeezed.map(\.width) == [1360, 120])
    // No room for the minimum: equal shares; junk weights count as 1.
    let narrow = tileFrames(in: CGRect(x: 0, y: 0, width: 200, height: 100), weights: [1, .nan, -3], horizontal: true, gap: 8)
    #expect(narrow.map(\.width) == [61, 62, 61])
}

@Test func tileAreaKeepsTheOuterGapsPerScreen() {
    let s = Settings()
    #expect(s.tileArea(on: builtIn) == area) // top gap 12 under the menu bar
    #expect(s.tileArea(on: external) == CGRect(x: 1524, y: 54, width: 1896, height: 1014)) // 54 for a status bar
}

// MARK: New windows

@Test func newWindowsTileTheCurrentWorkspaceAfterTheFocusedOne() {
    var s = tilingState([snapshot(1, onBuiltIn)])
    #expect(s.canvasFrame(1) == area)
    let commands = s.send(.system(.windowAppeared(snapshot(2, onExternal))))
    #expect(s.members(1) == [1, 2])
    #expect(moves(commands) == [wid(1): left, wid(2): right])
    _ = s.send(.system(.windowFocused(wid(1))))
    _ = s.send(.system(.windowAppeared(snapshot(3, onBuiltIn))))
    #expect(s.members(1) == [1, 3, 2])
}

@Test func startupGivesEachWindowItsOwnWorkspaceAndRulesKeepTheirs() {
    var settings = testSettings(layout: .tiles)
    settings.workspaceRules = "com.spotify.client=2, junk, dev.zed.Zed=x"
    let s = makeState([snapshot(1, onBuiltIn), snapshot(2, onBuiltIn), snapshot(3, onBuiltIn),
                       snapshot(4, onBuiltIn, app: "Spotify", bundle: "com.spotify.client")], settings: settings)
    #expect(s.members(1) == [1])
    #expect(s.members(2) == [4])
    #expect(s.members(3) == [2]) // 2 is kept for Spotify
    #expect(s.members(4) == [3])
    #expect(s.canvasFrame(1) == area)
    #expect(s.window(wid(1))?.parked == false)
    #expect(s.window(wid(2))?.parked == true)
}

@Test func someWindowsFloat() {
    var s = tilingState([snapshot(1, onBuiltIn, app: "Calculator", bundle: "com.apple.calculator")])
    var fixed = snapshot(2, onBuiltIn)
    fixed.isResizable = false
    _ = s.send(.system(.windowAppeared(fixed)))
    #expect(s.window(wid(1))?.workspace == nil && s.canvasFrame(1) == onBuiltIn)
    #expect(s.window(wid(2))?.workspace == nil)
    let floating = tilingState([snapshot(1, onBuiltIn)], settings: testSettings(layout: .floating))
    #expect(floating.window(wid(1))?.workspace == nil)
}

@Test func ruledWindowJoinsItsWorkspaceAndStaysParked() {
    var settings = testSettings(layout: .tiles)
    settings.workspaceRules = "com.spotify.client=2"
    var s = tilingState([snapshot(1, onBuiltIn)], settings: settings)
    _ = s.send(.system(.windowAppeared(snapshot(2, onBuiltIn, app: "Spotify", bundle: "com.spotify.client"))))
    #expect(s.members(2) == [2])
    #expect(s.window(wid(2))?.parked == true)
    #expect(s.currentWorkspace == 1)
    #expect(s.canvasFrame(2) == area.offsetBy(dx: 3672, dy: 0))
}

@Test func closingAWindowRetilesTheRest() {
    var s = twoTiles()
    let commands = s.send(.system(.windowClosed(wid(2))))
    #expect(moves(commands) == [wid(1): area])
    #expect(s.members(1) == [1])
    _ = s.send(.system(.windowClosed(wid(1))))
    #expect(s.workspaces.map(\.slot) == [1]) // the current one stays, empty
}

@Test func minimizedWindowsGiveUpTheirTile() {
    var s = twoTiles()
    #expect(moves(s.send(.system(.windowMinimized(wid(2), true)))) == [wid(1): area])
    #expect(moves(s.send(.system(.windowMinimized(wid(2), false)))) == [wid(1): left]) // 2 comes back where it was
}

@Test func fullScreenWindowsKeepTheirTileAndAreNeverMoved() {
    var s = twoTiles()
    // macOS full screen: the window fills the display in a Space of its own. Nothing moves.
    #expect(s.run(.system(.windowFullScreen(wid(2), true)), .system(.windowFrameChanged(wid(2), builtIn.frame))).isEmpty)
    #expect(s.advance(1).isEmpty)
    #expect(s.members(1) == [1, 2])
    // macOS puts it back where it was: still nothing moves.
    #expect(s.run(.system(.windowFrameChanged(wid(2), right)), .system(.windowFullScreen(wid(2), false))).isEmpty)
    #expect(s.advance(1).isEmpty)
}

@Test func fullScreenWindowsGoToTheirNewTileOnceBack() {
    var s = twoTiles()
    _ = s.run(.system(.windowFullScreen(wid(2), true)), .system(.windowFrameChanged(wid(2), builtIn.frame)))
    #expect(moves(s.send(.system(.windowClosed(wid(1))))).isEmpty) // its tile grows, but it stays put for now
    #expect(moves(s.run(.system(.windowFrameChanged(wid(2), right)), .system(.windowFullScreen(wid(2), false)))) == [wid(2): area])
}

@Test func aFloatingWindowFirstSeenInFullScreenKeepsTheFrameItComesBackAt() {
    var s = makeState([WindowSnapshot(id: wid(1), bundleID: nil, appName: "Safari", title: "Video", frame: builtIn.frame, isFullScreen: true)])
    let restored = CGRect(x: 200, y: 150, width: 900, height: 600)
    #expect(s.run(.system(.windowFrameChanged(wid(1), restored)), .system(.windowFullScreen(wid(1), false))).isEmpty)
    #expect(s.advance(1).isEmpty)
    #expect(s.deskFrame(s.window(wid(1))!) == restored)
}

// MARK: Landing

@Test func landingOnATiledWindowBringsItsWorkspaceToTheActiveScreen() {
    var settings = testSettings(layout: .tiles)
    settings.workspaceRules = "com.spotify.client=2"
    var s = tilingState([snapshot(1, onBuiltIn), snapshot(2, onBuiltIn, app: "Spotify", bundle: "com.spotify.client")], settings: settings)
    s.activeScreenID = external.id
    _ = s.send(.action(.toggleOverview))
    let commands = s.send(.landOn(wid(2)))
    #expect(s.deskCamera.toDesk(s.slots.origin(2), deskCenter: s.deskCenter) == external.frame.origin)
    #expect(s.currentWorkspace == 2)
    let tile = CGRect(x: 3684, y: 54, width: 1896, height: 1014) // laid out for the external display now
    #expect(s.canvasFrame(2) == tile)
    #expect(moves(commands)[wid(2)] == CGRect(x: 1524, y: 54, width: 1896, height: 1014))
    #expect(s.window(wid(1))?.parked == true)
    #expect(focuses(commands) == [wid(2)])
}

// MARK: Stacks

@Test func stackArrowsCycleThenFallThrough() {
    var s = tilingState([snapshot(1, onBuiltIn), snapshot(2, onBuiltIn), snapshot(3, onBuiltIn),
                         snapshot(4, onExternal, app: "Calculator", bundle: "com.apple.calculator")])
    _ = s.send(.system(.windowFocused(wid(1))))
    _ = s.send(.action(.layoutStack))
    #expect(s.mode(1) == .stack)
    for n: UInt32 in 1 ... 3 { #expect(s.canvasFrame(n) == area) }
    #expect(focuses(s.send(.action(.focus(.right)))) == [wid(2)])
    #expect(focuses(s.send(.action(.focus(.right)))) == [wid(3)])
    #expect(s.windows.last?.id == wid(3)) // in front
    #expect(focuses(s.send(.action(.focus(.right)))) == [wid(4)]) // past the end: the floating window that way
    _ = s.advance(1) // past the focus we asked for
    _ = s.send(.system(.windowFocused(wid(1))))
    #expect(focuses(s.send(.action(.focus(.left)))).isEmpty)
    #expect(focuses(s.send(.action(.focus(.up)))).isEmpty) // across a horizontal stack: nothing above
}

@Test func optionTabStepsThroughAStackAndWraps() {
    var s = tilingState([snapshot(1, onBuiltIn), snapshot(2, onBuiltIn), snapshot(3, onBuiltIn)])
    _ = s.send(.system(.windowFocused(wid(1))))
    _ = s.send(.action(.layoutStack))
    #expect(focuses(s.send(.action(.switchWindow(forward: true)))) == [wid(2)])
    #expect(focuses(s.send(.action(.switchWindow(forward: true)))) == [wid(3)])
    #expect(focuses(s.send(.action(.switchWindow(forward: true)))) == [wid(1)]) // wraps
    #expect(focuses(s.send(.action(.switchWindow(forward: false)))) == [wid(3)])
    #expect(!s.overview.isOpen) // no picker
    _ = s.send(.modifiersChanged([]))
    #expect(s.focused == wid(3))
}

// MARK: Layout keys

@Test func layoutKeysFlipTilesAndSwapStacks() {
    var s = twoTiles()
    _ = s.send(.action(.layoutTiles))
    #expect(s.workspaces.first?.orientation == .vertical)
    #expect(s.canvasFrame(1) == CGRect(x: 12, y: 50, width: 1488, height: 421))
    #expect(s.toast == nil) // the change is its own confirmation
    _ = s.send(.action(.layoutStack))
    #expect(s.mode(1) == .stack && s.canvasFrame(2) == area)
    _ = s.send(.action(.layoutStack))
    #expect(s.mode(1) == .tiles)
    _ = s.send(.action(.layoutTiles))
    #expect(s.canvasFrame(1) == left)
}

@Test func toggleFloatingGoesBackToTheLastFloatingFrame() {
    var s = twoTiles()
    _ = s.send(.action(.toggleFloating))
    #expect(s.window(wid(1))?.workspace == nil)
    #expect(s.canvasFrame(1) == onBuiltIn) // where it floated before it was tiled
    #expect(s.canvasFrame(2) == area)
    #expect(s.windows.last?.id == wid(1))
    _ = s.send(.action(.toggleFloating))
    #expect(s.members(1) == [2, 1])
}

@Test func toggleFloatingAwayFromItsOldSpotShrinksTheTile() {
    var s = twoTiles()
    _ = s.send(.action(.moveToWorkspace(2)))
    _ = s.send(.action(.toggleFloating))
    // 70% of the tile on slot 2, around its center, snapped to the 80-point grid.
    #expect(s.canvasFrame(1) == CGRect(x: 3920, y: 160, width: 1042, height: 595))
    #expect(s.window(wid(1))?.workspace == nil)
    _ = s.send(.action(.layoutTiles)) // floating: joins the workspace under it
    #expect(s.members(2) == [1])
}

@Test func layoutStackOnAFloatingWindowJoinsAsAStack() {
    var s = tilingState([snapshot(1, onBuiltIn, app: "Calculator", bundle: "com.apple.calculator")])
    _ = s.send(.system(.windowFocused(wid(1))))
    _ = s.send(.action(.layoutStack))
    #expect(s.members(1) == [1] && s.mode(1) == .stack)
}

// MARK: Workspace keys

@Test func workspaceKeysSettleOnTheirSlots() {
    var s = tilingState([snapshot(1, onBuiltIn)], settings: testSettings(animated: true, layout: .tiles))
    let commands = s.send(.action(.workspace(3)))
    #expect(s.deskCamera.toDesk(s.slots.origin(3), deskCenter: s.deskCenter) == .zero)
    #expect(s.currentWorkspace == 3)
    #expect(s.animator.isSettled && s.camera == s.deskCamera) // a cut, no flight
    #expect(s.workspaces.map(\.slot) == [1, 3]) // empty, but current
    #expect(s.window(wid(1))?.parked == true)
    #expect(moves(commands)[wid(1)] != nil)
    _ = s.send(.system(.windowAppeared(snapshot(2, onBuiltIn))))
    #expect(s.members(3) == [2])
    #expect(focuses(s.send(.action(.workspace(1)))) == [wid(1)])
    _ = s.send(.action(.workspace(5)))
    _ = s.send(.action(.workspace(1)))
    #expect(s.workspaces.map(\.slot) == [1, 3]) // the empty one went
}

@Test func workspaceStepSkipsEmptyOnesAndStopsAtTheEnds() {
    var s = tilingState([snapshot(1, onBuiltIn)])
    _ = s.send(.action(.workspace(4)))
    _ = s.send(.system(.windowAppeared(snapshot(2, onBuiltIn))))
    _ = s.send(.action(.workspace(1)))
    _ = s.send(.action(.workspaceStep(forward: true)))
    #expect(s.currentWorkspace == 4) // 2 and 3 are empty
    _ = s.send(.action(.workspaceStep(forward: true)))
    #expect(s.currentWorkspace == 4) // the last one: no wrap, as AeroSpace
    _ = s.send(.action(.workspaceStep(forward: false)))
    #expect(s.currentWorkspace == 1)
    _ = s.send(.action(.workspaceStep(forward: false)))
    #expect(s.currentWorkspace == 1)
}

@Test func moveToWorkspaceTakesTheCameraAlong() {
    var s = twoTiles()
    _ = s.send(.system(.windowFocused(wid(2))))
    let commands = s.send(.action(.moveToWorkspace(4)))
    #expect(s.members(1) == [1] && s.members(4) == [2])
    #expect(s.currentWorkspace == 4)
    #expect(focuses(commands) == [wid(2)])
    #expect(moves(commands)[wid(2)] == area)
    #expect(s.window(wid(1))?.parked == true)
    #expect(s.toast == nil) // a silent cut, as in AeroSpace
}

@Test func workspaceKeyInTheOverviewFliesZoomedOut() {
    var s = tilingState([snapshot(1, onBuiltIn)])
    _ = s.send(.action(.workspace(2)))
    _ = s.send(.system(.windowAppeared(snapshot(2, onBuiltIn))))
    _ = s.send(.action(.toggleOverview))
    let zoom = s.camera.zoom
    _ = s.send(.action(.workspace(1)))
    #expect(s.isOverview && s.camera.zoom == zoom)
    #expect(s.selection == wid(1))
    #expect(s.currentWorkspace == 1)
}

// MARK: Window keys on tiles

@Test func nudgeSwapsTilesThenCrossesToTheNextWorkspace() {
    var s = twoTiles()
    _ = s.send(.action(.nudge(.right)))
    #expect(s.members(1) == [2, 1])
    #expect(s.canvasFrame(1) == right && s.canvasFrame(2) == left)
    _ = s.send(.action(.nudge(.up))) // across the split: nothing
    #expect(s.members(1) == [2, 1])
    _ = s.send(.action(.nudge(.right))) // past the end
    #expect(s.members(2) == [1] && s.members(1) == [2])
    #expect(s.currentWorkspace == 2)
    _ = s.send(.action(.nudge(.left))) // back, at the end of workspace 1
    #expect(s.members(1) == [2, 1])
}

@Test func growAndShrinkMoveTheSplitByFiftyPoints() {
    var s = twoTiles()
    _ = s.send(.action(.grow))
    #expect(s.canvasFrame(1)?.width == 790 && s.canvasFrame(2)?.width == 690)
    _ = s.send(.action(.shrink))
    #expect(s.canvasFrame(1) == left && s.canvasFrame(2) == right)
    for _ in 0 ..< 30 { _ = s.send(.action(.shrink)) }
    #expect(s.canvasFrame(1)?.width == 120) // never under the minimum
}

@Test func fullscreenAndFillOnATileToggleBack() {
    var s = twoTiles()
    _ = s.send(.action(.fullscreen))
    #expect(s.canvasFrame(1) == builtIn.visibleFrame)
    _ = s.send(.action(.fullscreen))
    #expect(s.canvasFrame(1) == left)
    _ = s.send(.action(.fill))
    #expect(s.canvasFrame(1) == area && s.windows.last?.id == wid(1))
    #expect(s.canvasFrame(2) == right)
    _ = s.send(.action(.fill))
    #expect(s.canvasFrame(1) == left)
}

@Test func pinFloatsATileFirstAndArrangeLeavesTiles() {
    var s = twoTiles()
    _ = s.send(.action(.pin))
    #expect(s.window(wid(1))?.workspace == nil && s.window(wid(1))?.pinned == left)
    #expect(s.canvasFrame(2) == area)
    _ = s.send(.action(.toggleOverview))
    _ = s.send(.action(.arrange))
    #expect(s.canvasFrame(2) == area)
}

@Test func summonBringsATiledWindowIntoTheStartingWorkspace() {
    var s = twoTiles()
    _ = s.send(.action(.moveToWorkspace(3)))
    _ = s.send(.action(.workspace(1)))
    _ = s.send(.action(.toggleOverview))
    _ = s.send(.select(wid(1)))
    _ = s.send(.action(.summon))
    #expect(s.members(1) == [2, 1] && s.members(3) == nil)
    #expect(!s.isOverview && s.currentWorkspace == 1)
}

// MARK: The user resizes a tile

@Test func userResizeAlongTheSplitMovesTheNeighbour() {
    var s = twoTiles()
    let commands = s.send(.system(.windowFrameChanged(wid(1), CGRect(x: 12, y: 50, width: 840, height: 850), dragging: true)))
    #expect(s.canvasFrame(1) == CGRect(x: 12, y: 50, width: 840, height: 850))
    #expect(moves(commands) == [wid(2): CGRect(x: 860, y: 50, width: 640, height: 850)])
    // The left edge of the right tile moves the other one.
    _ = s.send(.system(.windowFrameChanged(wid(2), CGRect(x: 860, y: 50, width: 640, height: 850)))) // our move lands
    _ = s.send(.system(.windowFrameChanged(wid(2), right, dragging: true)))
    #expect(s.canvasFrame(1) == left && s.canvasFrame(2) == right)
}

@Test func userMoveOrResizeAcrossSnapsBack() {
    var s = twoTiles()
    #expect(moves(s.send(.system(.windowFrameChanged(wid(1), left.offsetBy(dx: 30, dy: 30))))) == [wid(1): left])
    _ = s.send(.system(.windowFrameChanged(wid(1), left)))
    #expect(moves(s.send(.system(.windowFrameChanged(wid(1), CGRect(x: 12, y: 50, width: 740, height: 500))))) == [wid(1): left])
    #expect(s.canvasFrame(1) == left)
}

@Test func anAppThatKeepsRefusingItsTileGetsItsWay() {
    var s = twoTiles()
    let refused = CGRect(x: 12, y: 50, width: 740, height: 700) // a maximum height, say
    #expect(moves(s.send(.system(.windowFrameChanged(wid(1), refused)))) == [wid(1): left])
    _ = s.advance(2.5) // our move never shows up, nor does sending it again
    #expect(moves(s.send(.system(.windowFrameChanged(wid(1), refused)))) == [wid(1): left])
    _ = s.advance(2.5)
    #expect(s.send(.system(.windowFrameChanged(wid(1), refused))).isEmpty) // given up
    #expect(s.canvasFrame(1)?.size == refused.size)
}

// MARK: Dragging in the overview

@Test func overviewDropMovesATileToAnotherWorkspace() {
    var settings = testSettings(layout: .tiles)
    settings.workspaceRules = "com.spotify.client=2"
    var s = tilingState([snapshot(1, onBuiltIn), snapshot(2, onBuiltIn), snapshot(3, onBuiltIn, app: "Spotify", bundle: "com.spotify.client")],
                        settings: settings)
    _ = s.send(.action(.toggleOverview))
    let z = s.camera.zoom
    _ = s.send(.gesture(.dragWindow(wid(1), CGVector(dx: 3672 * z, dy: 0))))
    #expect(s.dropIndicator == left.offsetBy(dx: 3672, dy: 0)) // before Spotify, which is to the right of its center
    _ = s.send(.gesture(.dragEnded(wid(1))))
    #expect(s.members(2) == [1, 3] && s.members(1) == [2])
    #expect(s.canvasFrame(2) == area && s.canvasFrame(1) == left.offsetBy(dx: 3672, dy: 0))
    #expect(s.dropIndicator == nil)
}

@Test func overviewDropReordersOrFloats() {
    var s = twoTiles()
    _ = s.send(.action(.toggleOverview))
    let z = s.camera.zoom
    _ = s.send(.gesture(.dragWindow(wid(1), CGVector(dx: 760 * z, dy: 0))))
    #expect(s.dropIndicator == right)
    _ = s.send(.gesture(.dragEnded(wid(1))))
    #expect(s.members(1) == [2, 1])
    _ = s.send(.gesture(.dragWindow(wid(1), CGVector(dx: 0, dy: 2000 * z)))) // below every workspace
    #expect(s.dropIndicator == snapToGrid(right.offsetBy(dx: 0, dy: 2000), grid: 80))
    _ = s.send(.gesture(.dragEnded(wid(1))))
    #expect(s.window(wid(1))?.workspace == nil)
    #expect(s.canvasFrame(1) == snapToGrid(right.offsetBy(dx: 0, dy: 2000), grid: 80))
    #expect(s.canvasFrame(2) == area)
}

// MARK: Undo

@Test func undoPutsTheLayoutBack() {
    var s = twoTiles()
    _ = s.send(.action(.layoutStack))
    _ = s.send(.action(.undo))
    #expect(s.mode(1) == .tiles && s.canvasFrame(1) == left)
    _ = s.send(.action(.redo))
    #expect(s.mode(1) == .stack && s.canvasFrame(1) == area)
    _ = s.send(.action(.undo))
    _ = s.send(.action(.grow))
    _ = s.send(.action(.moveToWorkspace(3)))
    _ = s.send(.action(.undo))
    #expect(s.members(1) == [1, 2] && s.window(wid(1))?.workspace == 1)
    #expect(s.canvasFrame(1)?.width == 790)
    _ = s.send(.action(.undo))
    #expect(s.canvasFrame(1) == left)
}

// MARK: Scene

@Test func sceneShowsWorkspacesAndFansStacks() {
    var s = twoTiles()
    _ = s.send(.action(.layoutStack))
    _ = s.send(.action(.toggleOverview))
    let scene = s.scene(for: builtIn)
    #expect(scene.workspaces == [SceneWorkspace(number: 1, canvasFrame: builtIn.frame, mode: .stack, isCurrent: true, windowCount: 2)])
    #expect(scene.windows.last?.id == wid(1) && scene.windows.last?.canvasFrame == area) // the selection, in front
    let behind = area.insetBy(dx: 24, dy: 0).offsetBy(dx: 0, dy: -14) // peeking out above, a little narrower
    #expect(scene.windows.first { $0.id == wid(2) }?.canvasFrame == behind)
    #expect(s.window(wid(2))?.frame == area) // only drawn that way
    #expect(scene.minimap?.workspaces == [builtIn.frame])
    // The peek is where the pointer finds it; selecting it brings it to the front.
    let peek = s.camera.toDesk(CGPoint(x: behind.midX, y: behind.minY + 4), deskCenter: s.deskCenter)
    let screenPoint = lensScreenPoint(peek, screenSize: builtIn.frame.size, look: s.look, transition: 1)
    #expect(s.window(atScreenPoint: screenPoint, on: builtIn) == wid(2))
    _ = s.send(.select(wid(2)))
    #expect(s.scene(for: builtIn).windows.last?.id == wid(2))

    var empty = tilingState()
    _ = empty.send(.action(.workspace(12)))
    var expected = SceneWorkspace(number: nil, canvasFrame: CGRect(origin: empty.slots.origin(12), size: builtIn.frame.size), mode: .tiles,
                                  isCurrent: true)
    expected.emptyMessage = "This workspace is empty"
    #expect(empty.scene(for: builtIn).workspaces == [expected])
    _ = empty.send(.action(.workspace(4)))
    #expect(empty.scene(for: builtIn).workspaces.first?.emptyMessage == "Workspace 4 is empty  {⌥⇧4} Move a window here")
}

// MARK: Persistence

@Test func layoutRoundTripsWithWorkspaces() throws {
    var s = twoTiles()
    _ = s.send(.action(.grow))
    _ = s.send(.action(.layoutTiles)) // vertical
    _ = s.send(.system(.windowAppeared(snapshot(3, onBuiltIn, title: "spare"))))
    _ = s.send(.system(.windowFocused(wid(3))))
    _ = s.send(.action(.moveToWorkspace(3)))
    _ = s.send(.action(.layoutStack))
    let layout = LayoutSnapshot(s)
    let url = try tempDir().appendingPathComponent("layout.json")
    try layout.save(to: url)
    let loaded = try #require(LayoutSnapshot.load(from: url))
    #expect(loaded == layout && loaded.version == 2)

    var next = CanvasState(screens: [builtIn, external], settings: testSettings(layout: .tiles), ownPID: 1, savedLayout: loaded)
    next.activeScreenID = builtIn.id
    #expect(next.slots == s.slots && next.currentWorkspace == 3)
    for n: UInt32 in [3, 2, 1] { // in another order than they were tiled
        _ = next.send(.system(.windowAppeared(snapshot(n + 10, onBuiltIn, title: n == 3 ? "spare" : "Ghostty \(n)"))))
    }
    #expect(next.members(1) == [11, 12] && next.members(3) == [13])
    #expect(next.workspaces.first?.orientation == .vertical && next.mode(3) == .stack)
    #expect(next.canvasFrame(11) == s.canvasFrame(1) && next.canvasFrame(12) == s.canvasFrame(2))
}

@Test func oldLayoutFilesStillLoadAndUnpark() throws {
    let url = try tempDir().appendingPathComponent("layout.json")
    try json("""
    {"version": 1, "camera": {"center": [1716, 540], "zoom": 1}, "deskCenter": [1716, 540], "windows": [
      {"id": {"pid": 100, "number": 1}, "bundleID": "com.mitchellh.ghostty", "appName": "Ghostty", "title": "Ghostty 1",
       "ordinal": 0, "frame": [[5000, 100], [800, 600]], "deskFrame": [[1511, 911], [800, 600]], "parked": true}]}
    """).write(to: url)
    let old = try #require(LayoutSnapshot.load(from: url))
    #expect(old.version == 1 && old.slots == nil && old.windows.first?.workspace == nil)
    #expect(moves(unparkCommands(old, screens: [builtIn, external])).keys.first == wid(1))
    // Coming back under tiling: the old file knew no workspaces, so the window is placed as new.
    let s = makeState([snapshot(9, onBuiltIn)], settings: testSettings(layout: .tiles), saved: old)
    #expect(s.window(wid(9))?.workspace == 1)
}

@Test func focusKeysAndASwitcherTapCutToTheWindowWithNoFlight() {
    var s = makeState([snapshot(1, onBuiltIn), snapshot(2, onBuiltIn)], settings: testSettings(animated: true, layout: .tiles))
    _ = s.send(.system(.windowFocused(wid(1))))
    _ = s.send(.action(.focus(.right))) // window 2 lives on workspace 2, off screen
    #expect(s.focused == wid(2) && s.currentWorkspace == 2)
    #expect(s.animator.isSettled && s.camera == s.deskCamera)
    _ = s.send(.action(.switchWindow(forward: true))) // ⌥Tab tapped: back to window 1
    _ = s.send(.modifiersChanged([]))
    #expect(s.focused == wid(1) && s.currentWorkspace == 1)
    #expect(s.animator.isSettled && s.camera == s.deskCamera)
}

@Test func aFloatingWindowStaysPutInItsWorkspaceAcrossSwitches() {
    var s = tilingState([snapshot(1, onBuiltIn)])
    // System Settings floats (a default floating app), half below workspace 1's screen (the external one is to the right).
    let settings = snapshot(2, CGRect(x: 500, y: 600, width: 740, height: 600), app: "System Settings", bundle: "com.apple.systempreferences")
    _ = s.send(.system(.windowAppeared(settings)))
    #expect(s.window(wid(2))?.workspace == nil)
    _ = s.send(.system(.windowFocused(wid(2)))) // a click on it
    #expect(s.currentWorkspace == 1)
    let home = s.deskCamera, frame = s.canvasFrame(2)!
    let view = s.deskCamera.toCanvas(builtIn.visibleFrame, deskCenter: s.deskCenter)
    #expect(view.contains(frame)) // moved just enough to be whole, the camera stayed on workspace 1
    #expect(frame.minX == 500) // only as far as needed
    _ = s.send(.action(.workspace(2)))
    _ = s.send(.action(.workspace(1)))
    #expect(s.deskCamera == home && s.canvasFrame(2) == frame) // where it was
    _ = s.send(.action(.focus(.right)))
    _ = s.send(.system(.windowFocused(wid(2))))
    #expect(s.deskCamera == home && s.canvasFrame(2) == frame)
}
