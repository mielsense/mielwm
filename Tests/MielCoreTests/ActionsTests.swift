import CoreGraphics
@testable import MielCore
import Testing

let onExternal = CGRect(x: 2000, y: 200, width: 900, height: 600)

func twoWindows() -> CanvasState {
    var s = makeState([snapshot(1, onBuiltIn), snapshot(2, onExternal, title: "fastfetch")])
    _ = s.send(.system(.windowFocused(wid(1))))
    return s
}

let filled = CGRect(x: 12, y: 50, width: 1488, height: 850) // built-in visible frame minus the 12 gap

// MARK: Fill and fullscreen

@Test func fillAndBackWhenUntouched() {
    var s = focusedState()
    #expect(moves(s.send(.action(.fill)))[wid(1)] == filled)
    _ = s.send(.system(.windowFrameChanged(wid(1), filled)))
    #expect(moves(s.send(.action(.fill)))[wid(1)] == onBuiltIn)
}

@Test func fillRestoreAfterMoveKeepsOldSizeWhereItIsNow() {
    var s = focusedState()
    _ = s.send(.action(.fill))
    _ = s.send(.system(.windowFrameChanged(wid(1), filled)))
    _ = s.send(.system(.windowFrameChanged(wid(1), filled.offsetBy(dx: 88, dy: 10)))) // user dragged it
    let back = moves(s.send(.action(.fill)))[wid(1)]
    #expect(back == CGRect(x: 444, y: 185, width: 800, height: 600))
}

@Test func fillAfterResizeFillsAgain() {
    var s = focusedState()
    _ = s.send(.action(.fill))
    _ = s.send(.system(.windowFrameChanged(wid(1), filled)))
    _ = s.send(.system(.windowFrameChanged(wid(1), CGRect(x: 12, y: 50, width: 1000, height: 700))))
    #expect(moves(s.send(.action(.fill)))[wid(1)] == filled)
}

@Test func restoredFrameRules() {
    let entry = RestoreEntry(before: CGRect(x: 0, y: 0, width: 400, height: 300), filled: CGRect(x: 10, y: 10, width: 1000, height: 800))
    #expect(restoredFrame(current: entry.filled, entry: entry) == entry.before)
    #expect(restoredFrame(current: entry.filled.offsetBy(dx: 100, dy: 0), entry: entry)
        == CGRect(x: 410, y: 260, width: 400, height: 300))
    #expect(restoredFrame(current: CGRect(x: 10, y: 10, width: 900, height: 800), entry: entry) == nil)
}

@Test func fullscreenOnItsScreenAndBack() {
    var s = focusedState()
    #expect(moves(s.send(.action(.fullscreen)))[wid(1)] == builtIn.visibleFrame)
    #expect(moves(s.send(.action(.fullscreen)))[wid(1)] == onBuiltIn)
}

@Test func overviewOverFullscreenWindowsItThenLandingRefullscreens() {
    var s = focusedState()
    _ = s.send(.action(.fullscreen))
    _ = s.send(.action(.toggleOverview))
    #expect(s.canvasFrame(1) == onBuiltIn) // back on the canvas, windowed
    let land = s.send(.key(.enter, []))
    #expect(moves(land)[wid(1)] == builtIn.visibleFrame)
    #expect(!s.isOverview)
    #expect(s.fullscreens[wid(1)]?.suspended == false)
}

@Test func escapeFromOverviewRefullscreens() {
    var s = focusedState()
    _ = s.send(.action(.fullscreen))
    _ = s.send(.action(.toggleOverview))
    // The real window never left fullscreen, so nothing moves; the canvas has it fullscreen again.
    #expect(moves(s.send(.key(.escape, []))).isEmpty)
    #expect(!s.isOverview && s.canvasFrame(1) == builtIn.visibleFrame && s.fullscreens[wid(1)]?.suspended == false)
}

@Test func landingOnAnotherWindowLeavesFullscreenWindowWindowed() {
    var s = twoWindows()
    _ = s.send(.action(.fullscreen))
    _ = s.send(.action(.toggleOverview))
    _ = s.send(.landOn(wid(2)))
    #expect(s.fullscreens[wid(1)] == nil)
    #expect(s.canvasFrame(1) == onBuiltIn)
    #expect(s.focused == wid(2))
}

// MARK: Pin, grow, shrink, nudge

@Test func pinnedWindowStaysPutWhileTheCanvasMoves() throws {
    var s = focusedState()
    _ = s.send(.action(.pin))
    #expect(moves(panDesk(&s, dx: -500))[wid(1)] == nil)
    _ = s.send(.action(.pin)) // unpinned where it now is on the canvas
    #expect(s.canvasFrame(1) == onBuiltIn.offsetBy(dx: 500, dy: 0))
    #expect(s.window(wid(1))?.pinned == nil)
}

@Test func growAndShrinkByOneGridStepAroundTheCenter() {
    var s = focusedState()
    #expect(moves(s.send(.action(.grow)))[wid(1)] == CGRect(x: 60, y: 60, width: 880, height: 680))
    _ = s.send(.action(.shrink))
    #expect(s.canvasFrame(1) == onBuiltIn)
}

@Test func nudgeMovesOneGridStep() {
    var s = focusedState()
    #expect(moves(s.send(.action(.nudge(.down))))[wid(1)] == onBuiltIn.offsetBy(dx: 0, dy: 80))
}

// MARK: Undo, redo

@Test func undoRedoNudge() {
    var s = focusedState()
    _ = s.send(.action(.nudge(.right)))
    _ = s.send(.action(.nudge(.right))) // a held key is one step
    #expect(moves(s.send(.action(.undo)))[wid(1)] == onBuiltIn)
    #expect(s.toast?.hasPrefix("Undone") == true)
    #expect(moves(s.send(.action(.redo)))[wid(1)] == onBuiltIn.offsetBy(dx: 160, dy: 0))
    _ = s.send(.action(.redo))
    #expect(s.toast == "Nothing to redo")
}

@Test func undoArrangeRestoresEveryWindow() {
    var s = twoWindows()
    _ = s.send(.action(.arrange))
    #expect(s.toast?.hasPrefix("Tidied 2 windows") == true)
    _ = s.send(.action(.undo))
    #expect(s.canvasFrame(1) == onBuiltIn)
    #expect(s.canvasFrame(2) == onExternal)
}

// MARK: Summon, navigation, MRU

@Test func summonBringsTheSelectionToWhereTheSessionStarted() {
    var s = twoWindows()
    _ = s.send(.action(.toggleOverview))
    _ = s.send(.select(wid(2)))
    let commands = s.send(.key(.enter, .shift))
    #expect(!s.isOverview)
    #expect(moves(commands)[wid(2)] == CGRect(x: 320, y: 160, width: 900, height: 600))
    #expect(focuses(commands) == [wid(2)])
    #expect(s.windows.last?.id == wid(2)) // in front
}

@Test func arrowFocusPicksTheWindowThatWay() {
    var s = twoWindows()
    let commands = s.send(.action(.focus(.right)))
    #expect(focuses(commands) == [wid(2)])
    #expect(s.focused == wid(2))
    #expect(s.send(.action(.focus(.right))).isEmpty) // nothing further right
}

@Test func navPrefersInLineOverNearerDiagonal() {
    let current = CGRect(x: 0, y: 0, width: 100, height: 100)
    let inLine = (id: wid(1), frame: CGRect(x: 300, y: 0, width: 100, height: 100))
    let diagonal = (id: wid(2), frame: CGRect(x: 150, y: 150, width: 100, height: 100))
    let steep = (id: wid(3), frame: CGRect(x: 120, y: 600, width: 100, height: 100))
    #expect(nearestWindow(from: current, direction: .right, candidates: [diagonal, inLine]) == wid(1))
    #expect(nearestWindow(from: current, direction: .right, candidates: [diagonal]) == wid(2))
    #expect(nearestWindow(from: current, direction: .right, candidates: [steep]) == nil) // beyond 45 degrees
    #expect(nearestWindow(from: current, direction: .left, candidates: [inLine, diagonal]) == nil)
    #expect(nearestWindow(from: current, direction: .down, candidates: [diagonal, steep]) == wid(2))
    #expect(nearestWindow(from: nil, direction: .up, candidates: [steep, inLine]) == wid(3))
}

@Test func mruOrder() {
    var m = MRU()
    for n: UInt32 in [1, 2, 3] { m.note(wid(n)) }
    #expect(m.order == [wid(3), wid(2), wid(1)])
    m.note(wid(1))
    #expect(m.order == [wid(1), wid(3), wid(2)])
    #expect(m.sorted([wid(4), wid(2), wid(1), wid(5)]) == [wid(1), wid(2), wid(4), wid(5)])
    m.remove(wid(3))
    #expect(m.order == [wid(1), wid(2)])
}

// MARK: Camera gestures

@Test func zoomAtPointKeepsThatPointAndClamps() {
    var s = twoWindows()
    _ = s.send(.action(.toggleOverview))
    let p = CGPoint(x: 400, y: 300), opened = s.camera.zoom
    let before = s.camera.toCanvas(p, deskCenter: s.deskCenter)
    _ = s.send(.gesture(.zoom(at: p, factor: 0.5)))
    let after = s.camera.toCanvas(p, deskCenter: s.deskCenter)
    #expect(abs(after.x - before.x) < 1e-6 && abs(after.y - before.y) < 1e-6)
    #expect(abs(s.camera.zoom - opened * 0.5) < 1e-9)
    _ = s.send(.gesture(.zoom(at: p, factor: 0.0001)))
    #expect(abs(s.camera.zoom - 0.05) < 1e-9)
    _ = s.send(.gesture(.zoom(at: p, factor: 1000)))
    #expect(abs(s.camera.zoom - 2.5) < 1e-9)
}

@Test func pinchFollowsTheFingersAndTakesOverAFlight() {
    var s = makeState([snapshot(1, onBuiltIn)], settings: testSettings(animated: true))
    _ = s.send(.action(.toggleOverview))
    _ = s.advance(0.1) // mid-flight
    let p = CGPoint(x: 400, y: 300), zoom = s.camera.zoom
    let before = s.camera.toCanvas(p, deskCenter: s.deskCenter)
    _ = s.send(.gesture(.pinch(at: p, factor: 1.1)))
    #expect(abs(s.camera.zoom - zoom * 1.1) < 1e-9) // at once, no glide
    let after = s.camera.toCanvas(p, deskCenter: s.deskCenter)
    #expect(abs(after.x - before.x) < 1e-6 && abs(after.y - before.y) < 1e-6)
    #expect(s.animator.target.center == s.camera.center) // the flight is over: nothing pulls the camera back
    _ = s.send(.gesture(.pan(CGVector(dx: 30, dy: -20))))
    #expect(abs(s.camera.toCanvas(p, deskCenter: s.deskCenter).x - (after.x - 30 / s.camera.zoom)) < 1e-6)
}

@Test func scrollZoomOutAtFullSizeOpensTheOverview() {
    var s = twoWindows()
    _ = s.send(.gesture(.zoom(at: CGPoint(x: 700, y: 400), factor: exp(-0.12))))
    #expect(s.isOverview)
    #expect(abs(s.camera.zoom - exp(-0.12)) < 1e-9)
}

@Test func overviewDragMovesWindowOnTheCanvasAndSnaps() {
    var s = twoWindows()
    _ = s.send(.action(.toggleOverview))
    let z = s.camera.zoom
    _ = s.send(.gesture(.dragWindow(wid(1), CGVector(dx: 30 * z, dy: 0))))
    #expect(s.canvasFrame(1).map { $0.isClose(to: onBuiltIn.offsetBy(dx: 30, dy: 0), tolerance: 1e-6) } == true)
    #expect(s.dropIndicator == CGRect(x: 160, y: 80, width: 800, height: 600))
    let commands = s.send(.gesture(.dragEnded(wid(1))))
    #expect(commands.isEmpty) // real windows move only on landing
    #expect(s.canvasFrame(1) == CGRect(x: 160, y: 80, width: 800, height: 600))
}

@Test func minimapJumpCentersThere() {
    var s = twoWindows()
    _ = s.send(.action(.toggleOverview))
    _ = s.send(.gesture(.minimapJump(CGPoint(x: 5000, y: 5000))))
    let center = s.camera.toCanvas(s.freeAreaCenter, deskCenter: s.deskCenter) // the middle of what the palette leaves free
    #expect(abs(center.x - 5000) < 1e-6 && abs(center.y - 5000) < 1e-6)
}

// MARK: Placement and tidy-up

@Test func parkCornerAvoidsTheAdjacentDisplay() {
    #expect(parkCorner(for: builtIn, among: [builtIn, external]) == .bottomLeft)
    #expect(parkCorner(for: external, among: [builtIn, external]) == .bottomRight)
    let slot = parkSlot(size: CGSize(width: 800, height: 600), on: external, corner: .bottomRight)
    #expect(slot == CGRect(x: 3431, y: 1079, width: 800, height: 600))
    let shown = slot.intersection(external.frame)
    #expect(shown.width == 1 && shown.height == 1)
}

@Test func autoPlaceNeverOverlaps() {
    var occupied: [CGRect] = []
    for _ in 0 ..< 12 {
        let r = autoPlace(size: CGSize(width: 600, height: 400), around: CGPoint(x: 700, y: 450), occupied: occupied,
                          gap: 40, screenSize: CGSize(width: 1512, height: 874), grid: nil)
        for o in occupied { #expect(!r.insetBy(dx: -19, dy: -19).intersects(o)) }
        occupied.append(r)
    }
    #expect(occupied[0].center == CGPoint(x: 700, y: 450)) // the first goes right where the camera is
}

@Test func snapToGridRoundsTheOrigin() {
    #expect(snapToGrid(CGRect(x: 41, y: 119, width: 333, height: 222), grid: 80) == CGRect(x: 80, y: 80, width: 333, height: 222))
}

@Test func unparkFrameMovesHiddenWindowsOntoTheNearestScreen() {
    let hidden = CGRect(x: -799, y: 911, width: 800, height: 600)
    let back = onScreenFrame(hidden, screens: [builtIn, external])
    #expect(builtIn.visibleFrame.contains(back))
    #expect(onScreenFrame(onBuiltIn, screens: [builtIn]) == onBuiltIn)
}

func item(_ n: UInt32, _ frame: CGRect, app: String, bundle: String, title: String) -> ArrangeItem {
    ArrangeItem(id: wid(n), frame: frame, category: WindowCategory(bundleID: bundle, appName: app, title: title),
                tokens: contextTokens(title: title, appName: app))
}

@Test func arrangeGroupsByContextWithNoOverlaps() throws {
    let items = [
        item(1, CGRect(x: 0, y: 0, width: 800, height: 600), app: "Ghostty", bundle: "com.mitchellh.ghostty", title: "mielwm: swift test"),
        item(2, CGRect(x: 50, y: 50, width: 820, height: 610), app: "Ghostty", bundle: "com.mitchellh.ghostty", title: "htop"),
        item(3, CGRect(x: 3000, y: 900, width: 1200, height: 800), app: "Safari", bundle: "com.apple.Safari", title: "mielwm on GitHub"),
        item(4, CGRect(x: -900, y: 40, width: 1000, height: 700), app: "Slack", bundle: "com.tinyspeck.slackmacgap", title: "general"),
        item(5, CGRect(x: 10, y: 10, width: 640, height: 480), app: "Music", bundle: "com.apple.Music", title: "Music"),
        item(6, CGRect(x: 20, y: 20, width: 1300, height: 900), app: "Safari", bundle: "com.apple.Safari", title: "Hacker News"),
    ]
    let out = arrange(items, options: ArrangeOptions(), center: CGPoint(x: 700, y: 450), maxRowWidth: 2800)
    #expect(out.count == items.count)
    let frames = items.map { out[$0.id]! }
    for i in frames.indices {
        #expect(frames[i].minX.truncatingRemainder(dividingBy: 80) == 0 && frames[i].minY.truncatingRemainder(dividingBy: 80) == 0)
        for j in frames.indices where j > i { #expect(!frames[i].intersects(frames[j])) }
    }
    // The terminal and the browser page about one project form one group nothing else cuts into.
    let project = out[wid(1)]!.union(out[wid(3)]!)
    for n: UInt32 in [2, 4, 5, 6] { #expect(!project.intersects(out[wid(n)]!)) }
    // Sizes stay within the resize limit.
    for it in items {
        let f = out[it.id]!
        #expect(abs(f.width - it.frame.width) / it.frame.width <= 0.15 + 1e-9)
        #expect(abs(f.height - it.frame.height) / it.frame.height <= 0.15 + 1e-9)
    }
}

@Test func arrangeGivesSimilarWindowsOneSize() {
    let items = [
        item(1, CGRect(x: 0, y: 0, width: 800, height: 600), app: "Ghostty", bundle: "com.mitchellh.ghostty", title: "one"),
        item(2, CGRect(x: 0, y: 0, width: 840, height: 630), app: "Ghostty", bundle: "com.mitchellh.ghostty", title: "two"),
    ]
    let out = arrange(items, options: ArrangeOptions(), center: .zero, maxRowWidth: 3000)
    #expect(out[wid(1)]!.size == out[wid(2)]!.size)
    let off = arrange(items, options: ArrangeOptions(sizeSimilarity: 0.01), center: .zero, maxRowWidth: 3000)
    #expect(off[wid(1)]!.size == CGSize(width: 800, height: 640))
    #expect(off[wid(2)]!.size == CGSize(width: 880, height: 640))
}
