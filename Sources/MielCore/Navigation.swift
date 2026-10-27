import CoreGraphics
import Foundation

/// The nearest window that way, from where the windows are now (Phantomat
/// moveSelection, the rules Android uses for arrow keys). A candidate has to
/// reach further that way than the current window with both edges, and some
/// of it has to lie within 45 degrees of that side. One in line with the
/// current window (their spans across the arrow overlap) beats one that is
/// not, unless, going up or down, that one is wholly nearer; otherwise the
/// nearer wins, sideways offset counting less than distance along the arrow.
/// With no current window, the first candidate.
public func nearestWindow(from current: CGRect?, direction: Direction,
                          candidates: [(id: WindowID, frame: CGRect)]) -> WindowID? {
    guard let current else { return candidates.first?.id }
    let horizontal = direction == .left || direction == .right
    let forward = direction == .right || direction == .down

    struct Along { var near, far, acrossMin, acrossMax: Double }
    func along(_ r: CGRect) -> Along {
        let lo = horizontal ? r.minX : r.minY, hi = horizontal ? r.maxX : r.maxY
        let a = horizontal ? r.minY : r.minX, b = horizontal ? r.maxY : r.maxX
        return forward ? Along(near: lo, far: hi, acrossMin: a, acrossMax: b)
            : Along(near: -hi, far: -lo, acrossMin: a, acrossMax: b)
    }

    struct Candidate { var id: WindowID; var gap, reach, weighted: Double; var inLine, beyond: Bool }
    func better(_ a: Candidate, _ b: Candidate) -> Bool {
        if a.inLine != b.inLine {
            let inside = a.inLine ? a : b, outside = a.inLine ? b : a
            let insideWins = !outside.beyond || horizontal || inside.gap < outside.reach
            return a.inLine ? insideWins : !insideWins
        }
        return a.weighted < b.weighted
    }

    let from = along(current)
    var best: Candidate?
    for (id, frame) in candidates {
        let to = along(frame)
        guard to.near > from.near, to.far > from.far else { continue }
        let reach = to.far - from.far
        let aside = max(0, to.acrossMin - from.acrossMax, from.acrossMin - to.acrossMax)
        guard aside < reach else { continue }
        let gap = max(0, to.near - from.far)
        let offset = (to.acrossMin + to.acrossMax - from.acrossMin - from.acrossMax) / 2
        let c = Candidate(id: id, gap: gap, reach: reach, weighted: 13 * gap * gap + offset * offset,
                          inLine: to.acrossMax > from.acrossMin && to.acrossMin < from.acrossMax,
                          beyond: to.near >= from.far)
        if best.map({ better(c, $0) }) ?? true { best = c }
    }
    return best?.id
}

/// Most recently used first.
public struct MRU: Hashable, Codable, Sendable {
    public private(set) var order: [WindowID] = []

    public init(_ order: [WindowID] = []) { self.order = order }

    public mutating func note(_ id: WindowID) {
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
    }

    public mutating func remove(_ id: WindowID) { order.removeAll { $0 == id } }

    /// `ids` most recent first; ones never used keep their order at the end.
    public func sorted(_ ids: [WindowID]) -> [WindowID] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        return ids.enumerated().sorted { a, b in
            (rank[a.element] ?? Int.max, a.offset) < (rank[b.element] ?? Int.max, b.offset)
        }.map(\.element)
    }
}

/// "on screen", or an arrow and a distance in screens, as the palette shows it.
public func directionHint(for frame: CGRect, viewCenter: CGPoint, viewSize: CGSize) -> String {
    guard viewSize.width > 0, viewSize.height > 0 else { return "" }
    let dx = (frame.midX - viewCenter.x) / viewSize.width
    let dy = (frame.midY - viewCenter.y) / viewSize.height
    let distance = (dx * dx + dy * dy).squareRoot()
    if distance < 0.55 { return "on screen" }
    let arrows = ["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"]
    let index = (Int((atan2(dy, dx) / (.pi / 4)).rounded()) + 8) % 8
    let tenths = (distance * 10).rounded() / 10 // "1 screen away", "1.5 screens away"
    let amount = tenths == tenths.rounded() ? "\(Int(tenths)) screen\(tenths == 1 ? "" : "s")" : String(format: "%.1f screens", tenths)
    return "\(arrows[index]) \(amount) away"
}
