import CoreGraphics

/// The union of all screen frames: what the contract calls the desk.
public func deskRect(_ screens: [ScreenInfo]) -> CGRect {
    screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
}

public func deskCenter(_ screens: [ScreenInfo]) -> CGPoint {
    let desk = deskRect(screens)
    return desk.isNull ? .zero : desk.center
}

extension CGRect {
    /// Area of the part inside `other`, 0 when they are apart.
    func overlapArea(_ other: CGRect) -> CGFloat {
        let i = intersection(other)
        return i.isNull ? 0 : i.width * i.height
    }

    func distance(to p: CGPoint) -> CGFloat {
        let dx = Swift.max(minX - p.x, 0, p.x - maxX)
        let dy = Swift.max(minY - p.y, 0, p.y - maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    func isClose(to other: CGRect, tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }

    func offsetBy(_ v: CGVector) -> CGRect { offsetBy(dx: v.dx, dy: v.dy) }

    func centered(at p: CGPoint) -> CGRect {
        CGRect(x: p.x - width / 2, y: p.y - height / 2, width: width, height: height)
    }
}

/// How much of `rect` the screens show, in square points.
func visibleArea(_ rect: CGRect, on screens: [ScreenInfo]) -> CGFloat {
    screens.reduce(0) { $0 + rect.overlapArea($1.frame) }
}

/// The screen that shows most of `rect`, nil when none shows any of it.
public func screenShowingMost(_ rect: CGRect, of screens: [ScreenInfo]) -> ScreenInfo? {
    let best = screens.max { rect.overlapArea($0.frame) < rect.overlapArea($1.frame) }
    return best.flatMap { rect.overlapArea($0.frame) > 0 ? $0 : nil }
}

func nearestScreen(to p: CGPoint, of screens: [ScreenInfo]) -> ScreenInfo? {
    screens.min { $0.frame.distance(to: p) < $1.frame.distance(to: p) }
}
