import CoreGraphics
import Foundation

/// The canvas has one lattice: snap the origin to it.
func snapToGrid(_ r: CGRect, grid: Double) -> CGRect {
    guard grid > 0 else { return r }
    return CGRect(x: (r.minX / grid).rounded() * grid, y: (r.minY / grid).rounded() * grid, width: r.width, height: r.height)
}

/// A free spot for a new window near `center`: the center first, then rings
/// of window-sized steps outward. `occupied`
/// are the other windows' canvas frames, kept `gap` apart. Odd sizes become
/// 42% of the screen.
func autoPlace(size: CGSize, around center: CGPoint, occupied: [CGRect], gap: Double,
               screenSize: CGSize, grid: Double?) -> CGRect {
    var size = size
    if size.width <= 1 || size.height <= 1 || size.width > screenSize.width * 0.9 || size.height > screenSize.height * 0.9 {
        size = CGSize(width: screenSize.width * 0.42, height: screenSize.height * 0.42)
    }
    let blocked = occupied.map { $0.insetBy(dx: -gap / 2, dy: -gap / 2) }
    func free(_ r: CGRect) -> Bool { !blocked.contains { $0.intersects(r) } }
    let base = CGRect(origin: .zero, size: size).centered(at: center)
    var placement = base
    if !free(base) {
        search: for ring in 1 ... 16 {
            let r = Double(ring)
            for (dx, dy) in [(r, 0.0), (-r, 0), (0, r), (0, -r), (r, r), (-r, r), (r, -r), (-r, -r)] {
                let candidate = base.offsetBy(dx: dx * (size.width + gap), dy: dy * (size.height + gap))
                if free(candidate) { placement = candidate; break search }
            }
        }
    }
    return grid.map { snapToGrid(placement, grid: $0) } ?? placement
}

// MARK: - Fill (⌥T) and fullscreen-on-its-screen (⌥F)

/// What Fill covers: the screen minus menu bar and Dock, with `gap` all round.
func fillArea(on screen: ScreenInfo, gap: Double) -> CGRect {
    screen.visibleFrame.insetBy(dx: gap, dy: gap)
}

/// The frame a window had before Fill or fullscreen, and the one it got.
public struct RestoreEntry: Hashable, Codable, Sendable {
    public var before: CGRect
    public var filled: CGRect
}

/// Fill again: back exactly where and how big it was if untouched since;
/// moved since: its old size around where it is now; resized since: nil
/// (it fills again).
func restoredFrame(current: CGRect, entry: RestoreEntry) -> CGRect? {
    guard current.size.isClose(to: entry.filled.size) else { return nil }
    if current.origin.isClose(to: entry.filled.origin) { return entry.before }
    return CGRect(origin: .zero, size: entry.before.size).centered(at: current.center)
}

extension CGSize {
    func isClose(to o: CGSize, tolerance: CGFloat = 1) -> Bool {
        abs(width - o.width) <= tolerance && abs(height - o.height) <= tolerance
    }
}

extension CGPoint {
    func isClose(to o: CGPoint, tolerance: CGFloat = 1) -> Bool {
        abs(x - o.x) <= tolerance && abs(y - o.y) <= tolerance
    }
}

// MARK: - Parking

/// A window off camera still has to be somewhere: macOS keeps windows on a
/// screen. Like AeroSpace, it goes to a bottom corner of a display's visible
/// frame with 1 point showing (its top-left or top-right corner), the corner
/// that does not touch another display.
public enum ParkCorner: String, Hashable, Codable, Sendable { case bottomLeft, bottomRight }

/// AeroSpace's optimalHideCorner: probe just outside each bottom corner; the
/// corner whose probes land on fewer other displays wins.
func parkCorner(for screen: ScreenInfo, among screens: [ScreenInfo]) -> ParkCorner {
    let f = screen.frame
    let xOff = f.width * 0.1, yOff = f.height * 0.1
    func score(_ side: CGFloat, _ inward: CGFloat) -> Int {
        let p1 = CGPoint(x: side, y: f.maxY - yOff) // beside the screen
        let p2 = CGPoint(x: inward, y: f.maxY + 2) // below it
        let p3 = CGPoint(x: side, y: f.maxY + 2) // diagonal
        return screens.reduce(0) { total, s in
            total + ([p1, p3].filter { s.frame.contains($0) }.count * 10) + (s.frame.contains(p2) ? 1 : 0)
        }
    }
    let left = score(f.minX - 2, f.minX + xOff), right = score(f.maxX + 2, f.maxX - xOff)
    return left < right ? .bottomLeft : .bottomRight
}

/// Where a window of `size` parks on `screen`.
func parkSlot(size: CGSize, on screen: ScreenInfo, corner: ParkCorner) -> CGRect {
    let v = screen.visibleFrame
    let x = corner == .bottomRight ? v.maxX - 1 : v.minX + 1 - size.width
    return CGRect(x: x, y: v.maxY - 1, width: size.width, height: size.height)
}

/// True when no screen shows more than a sliver of `frame` (3 points or
/// less across): a window parked by us or hidden by AeroSpace, or off every screen.
public func isHiddenFrame(_ frame: CGRect, screens: [ScreenInfo]) -> Bool {
    screens.allSatisfy { s in
        let i = frame.intersection(s.frame)
        return i.isNull || i.width <= 3 || i.height <= 3
    }
}

/// A frame every screen shows: `frame` itself when a screen shows it, else
/// moved (and if need be shrunk) into the visible frame of the nearest
/// screen. Used to unpark everything on quit and for crash recovery.
func onScreenFrame(_ frame: CGRect, screens: [ScreenInfo]) -> CGRect {
    guard isHiddenFrame(frame, screens: screens), let screen = nearestScreen(to: frame.center, of: screens) else { return frame }
    let v = screen.visibleFrame
    let w = min(frame.width, v.width), h = min(frame.height, v.height)
    return CGRect(x: min(max(frame.minX, v.minX), v.maxX - w), y: min(max(frame.minY, v.minY), v.maxY - h), width: w, height: h)
}
