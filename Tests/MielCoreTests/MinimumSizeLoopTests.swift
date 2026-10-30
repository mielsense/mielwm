import CoreGraphics
import Foundation
@testable import MielCore
import Testing

/// Plays apps with minimum widths. `echo`: the app first takes our frame, then corrects it (late refusal).
func play(_ s: inout CanvasState, _ first: [WindowCommand], minWidth: [UInt32: CGFloat], maxHeight: [UInt32: CGFloat] = [:],
          echo: Bool, rounds: Int = 40) -> Int {
    var commands = first, n = 0
    while n < rounds {
        let ms = moves(commands)
        if ms.isEmpty { return n }
        n += 1
        commands = []
        for (id, f) in ms {
            var r = f
            if let m = minWidth[id.number], r.width < m { r.size.width = m }
            if let m = maxHeight[id.number], r.height > m { r.size.height = m }
            if echo { commands += s.send(.system(.windowFrameChanged(id, f))) }
            let c = s.send(.system(.windowFrameChanged(id, r)))
            commands += c
        }
        commands += s.advance(1.5)
    }
    return n
}

@Test func minSizeMiddleTileWithMinWidthLateRefusal() {
    var s = tilingState([snapshot(1, onBuiltIn), snapshot(2, onBuiltIn), snapshot(3, onBuiltIn)])
    s.confirmMoves()
    let start = s.send(.action(.refresh))
    // window 2 (middle) cannot go under 800 wide; nudge it by retiling
    var settings = s.settings; settings.gapInnerHorizontal += 1
    let first = s.send(.setSettings(settings)) + start
    let n = play(&s, first, minWidth: [2: 800], echo: true)
    #expect(n < 40)
}

@Test func minSizeMiddleTileWithMinWidthImmediateRefusal() {
    var s = tilingState([snapshot(1, onBuiltIn), snapshot(2, onBuiltIn), snapshot(3, onBuiltIn)])
    s.confirmMoves()
    var settings = s.settings; settings.gapInnerHorizontal += 1
    let n = play(&s, s.send(.setSettings(settings)), minWidth: [2: 800], echo: false)
    #expect(n < 40)
}

@Test func minSizeTwoMinWidthsLateRefusal() {
    var s = tilingState([snapshot(1, onBuiltIn), snapshot(2, onBuiltIn)])
    s.confirmMoves()
    var settings = s.settings; settings.gapInnerHorizontal += 1
    let n = play(&s, s.send(.setSettings(settings)), minWidth: [1: 800, 2: 800], echo: true)
    #expect(n < 40)
}

@Test func minSizeMaxHeightLateRefusal() {
    var s = tilingState([snapshot(1, onBuiltIn), snapshot(2, onBuiltIn)])
    s.confirmMoves()
    var settings = s.settings; settings.gapInnerHorizontal += 1
    let n = play(&s, s.send(.setSettings(settings)), minWidth: [:], maxHeight: [1: 700], echo: true)
    #expect(n < 40)
}

@Test func minSizeMiddleDirect() {
    for echo in [true, false] {
        var s = tilingState([snapshot(1, onBuiltIn), snapshot(2, onBuiltIn), snapshot(3, onBuiltIn)])
        s.confirmMoves()
        var f = s.canvasFrame(2)!; f.size.width = 800
        let n = play(&s, s.send(.system(.windowFrameChanged(wid(2), f, dragging: true))), minWidth: [2: 800], echo: echo)
        #expect(n < 40)
    }
}

@Test func minSizeTwoDirect() {
    for echo in [true, false] {
        var s = tilingState([snapshot(1, onBuiltIn), snapshot(2, onBuiltIn)])
        s.confirmMoves()
        var f = s.canvasFrame(1)!; f.size.width = 800
        let n = play(&s, s.send(.system(.windowFrameChanged(wid(1), f, dragging: true))), minWidth: [1: 800, 2: 800], echo: echo)
        #expect(n < 40)
    }
}

@Test func minSizeMiddleTooBig() {
    for echo in [true, false] {
        var s = tilingState([snapshot(1, onBuiltIn), snapshot(2, onBuiltIn), snapshot(3, onBuiltIn), snapshot(4, onBuiltIn)])
        _ = s.send(.system(.windowFocused(wid(1))))
        s.confirmMoves()
        let order = s.members(1)!
        let mid = order[1]
        var f = s.canvasFrame(mid)!; f.size.width = 900
        let n = play(&s, s.send(.system(.windowFrameChanged(wid(mid), f, dragging: true))), minWidth: [mid: 900], echo: echo, rounds: 12)
        #expect(n < 12)
    }
}

@Test func minSizeSlowApp() {
    var s = tilingState([snapshot(1, onBuiltIn), snapshot(2, onBuiltIn), snapshot(3, onBuiltIn), snapshot(4, onBuiltIn)])
    _ = s.send(.system(.windowFocused(wid(1))))
    s.confirmMoves()
    var f = s.canvasFrame(2)!; f.size.width = 900
    var commands = s.send(.system(.windowFrameChanged(wid(2), f, dragging: true))), n = 0
    while n < 12, let m = moves(commands)[wid(2)] {
        n += 1
        commands = s.advance(1.5) // the app answers late
        var r = m; r.size.width = 900
        commands += s.send(.system(.windowFrameChanged(wid(2), r)))
    }
    #expect(n < 12)
}
