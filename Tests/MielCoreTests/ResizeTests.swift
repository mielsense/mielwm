import CoreGraphics
@testable import MielCore
import Testing

// resize by an amount, along the split for tiles, one side or both for a floating window.

@Test func resizeCommandsWithBadAmountsAreRefused() {
    #expect(Action(command: "resize smart +50")?.command == "resize smart +50")
    for bad in ["resize width 800", "resize smart +0", "resize diagonal +5", "resize smart", "resize width -x"] {
        #expect(Action(command: bad) == nil, "\(bad)")
    }
}

@Test func resizeMovesTheSplitByTheAmountOnlyAlongIt() {
    var s = twoTiles() // side by side
    _ = s.send(.action(.resize(.smart, 100)))
    #expect(s.canvasFrame(1)?.width == 840 && s.canvasFrame(2)?.width == 640)
    _ = s.send(.action(.resize(.height, 100))) // across the split: nothing to change
    #expect(s.canvasFrame(1)?.width == 840 && s.canvasFrame(1)?.height == left.height)
    _ = s.send(.action(.resize(.width, -100)))
    #expect(s.canvasFrame(1) == left && s.canvasFrame(2) == right)
}

@Test func resizeAFloatingWindowOneSideAroundItsCenter() {
    var s = focusedState()
    _ = s.send(.action(.resize(.width, 100)))
    #expect(s.canvasFrame(1) == CGRect(x: 50, y: 100, width: 900, height: 600))
    _ = s.send(.action(.resize(.height, -40)))
    #expect(s.canvasFrame(1) == CGRect(x: 50, y: 120, width: 900, height: 560))
    _ = s.send(.action(.resize(.smart, -100)))
    #expect(s.canvasFrame(1) == CGRect(x: 100, y: 170, width: 800, height: 460))
}
