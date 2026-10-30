import CoreGraphics
@testable import MielCore
import Testing

// Pointer gestures on windows: resizing by a corner, and dragging a pinned window.

@Test func resizingByTheBottomRightCornerKeepsTheTopLeft() {
    var s = focusedState()
    let out = s.send(.gesture(.resizeWindow(wid(1), .bottomRight, CGVector(dx: 40, dy: 30))))
    #expect(moves(out)[wid(1)] == CGRect(x: 100, y: 100, width: 840, height: 630))
}

@Test func resizingByTheTopLeftCornerKeepsTheBottomRight() {
    var s = focusedState()
    _ = s.send(.gesture(.resizeWindow(wid(1), .topLeft, CGVector(dx: 40, dy: 30))))
    #expect(s.canvasFrame(1) == CGRect(x: 140, y: 130, width: 760, height: 570))
}

@Test func resizingStopsAtTheSmallestWindow() {
    var s = focusedState()
    _ = s.send(.gesture(.resizeWindow(wid(1), .topRight, CGVector(dx: -5000, dy: 5000))))
    let frame = s.canvasFrame(1)
    #expect(frame?.size == CGSize(width: 120, height: 80))
    #expect(frame?.minX == 100 && frame?.maxY == 700) // the left and bottom edges stay
}

@Test func aWindowThatCannotResizeIgnoresTheGesture() {
    var fixed = snapshot(1, onBuiltIn)
    fixed.isResizable = false
    var s = makeState([fixed])
    #expect(s.send(.gesture(.resizeWindow(wid(1), .bottomRight, CGVector(dx: 40, dy: 30)))).isEmpty)
    #expect(s.canvasFrame(1) == onBuiltIn)
}

@Test func resizingIsOneStepToUndo() {
    var s = focusedState()
    for _ in 0 ..< 3 { _ = s.send(.gesture(.resizeWindow(wid(1), .bottomRight, CGVector(dx: 10, dy: 10)))) }
    _ = s.send(.gesture(.dragEnded(wid(1))))
    _ = s.send(.action(.undo))
    #expect(s.canvasFrame(1) == onBuiltIn)
}

@Test func draggingAPinnedWindowMovesItsPinNotItsCanvasFrame() throws {
    var s = focusedState()
    _ = s.send(.action(.pin))
    let pin = try #require(s.window(wid(1))?.pinned), frame = s.canvasFrame(1)
    _ = s.send(.gesture(.dragWindow(wid(1), CGVector(dx: 50, dy: 20))))
    #expect(s.window(wid(1))?.pinned == pin.offsetBy(dx: 50, dy: 20))
    #expect(s.canvasFrame(1) == frame)
}
