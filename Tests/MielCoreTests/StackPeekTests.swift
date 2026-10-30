import CoreGraphics
import Foundation
@testable import MielCore
import Testing

// Peek edges: the windows behind a stack's front one show their edges.

@Test func stackFramesPeekEitherSideOfTheFront() {
    let r = CGRect(x: 0, y: 0, width: 1000, height: 800)
    #expect(stackFrames(in: r, count: 3, front: 1, horizontal: true, peek: 0) == [r, r, r])
    #expect(stackFrames(in: r, count: 1, front: 0, horizontal: true, peek: 8) == [r])
    let mid = CGRect(x: 8, y: 0, width: 984, height: 800)
    #expect(stackFrames(in: r, count: 4, front: 1, horizontal: true, peek: 8)
        == [mid.offsetBy(dx: -8, dy: 0), mid, mid.offsetBy(dx: 8, dy: 0), mid.offsetBy(dx: 8, dy: 0)])
    #expect(stackFrames(in: r, count: 2, front: 0, horizontal: false, peek: 6)
        == [CGRect(x: 0, y: 6, width: 1000, height: 788), CGRect(x: 0, y: 12, width: 1000, height: 788)])
}

@Test func peekEdgesMoveWithTheFrontWindow() {
    var settings = testSettings(layout: .tiles)
    settings.stackPeek = 8
    var s = stacked(settings: settings)
    let mid = area.insetBy(dx: 8, dy: 0)
    #expect(s.canvasFrame(1) == mid && s.canvasFrame(2) == mid.offsetBy(dx: 8, dy: 0) && s.canvasFrame(3) == mid.offsetBy(dx: 8, dy: 0))
    let commands = s.send(.action(.focus(.right)))
    #expect(focuses(commands) == [wid(2)])
    #expect(moves(commands)[wid(1)] == mid.offsetBy(dx: -8, dy: 0)) // the real windows follow
    #expect(s.canvasFrame(2) == mid && s.canvasFrame(3) == mid.offsetBy(dx: 8, dy: 0))
    _ = s.advance(1) // past the focus we asked for
    _ = s.send(.system(.windowFocused(wid(3)))) // focus from outside, a click or ⌘Tab
    #expect(s.canvasFrame(3) == mid && s.canvasFrame(2) == mid.offsetBy(dx: -8, dy: 0))
}

@Test func stackPeekIsASettingFrom0To16() {
    var s = Settings()
    #expect(s.stackPeek == 0)
    s.set(.number(40), forKey: "layout:stack_peek")
    #expect(s.stackPeek == 16)
}
