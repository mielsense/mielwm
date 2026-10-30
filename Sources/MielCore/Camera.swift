import CoreGraphics

/// One camera for all screens ("your screens are one desk"). `center` is the
/// canvas point shown at the center of the desk (the union of all screen
/// frames). At zoom 1 and center == desk center, canvas coordinates equal
/// global screen coordinates.
public struct Camera: Hashable, Codable, Sendable {
    public var center: CGPoint
    public var zoom: CGFloat

    public init(center: CGPoint, zoom: CGFloat = 1) {
        self.center = center
        self.zoom = zoom
    }

    public func toDesk(_ p: CGPoint, deskCenter: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - center.x) * zoom + deskCenter.x,
                y: (p.y - center.y) * zoom + deskCenter.y)
    }

    public func toCanvas(_ p: CGPoint, deskCenter: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - deskCenter.x) / zoom + center.x,
                y: (p.y - deskCenter.y) / zoom + center.y)
    }

    public func toDesk(_ r: CGRect, deskCenter: CGPoint) -> CGRect {
        let o = toDesk(r.origin, deskCenter: deskCenter)
        return CGRect(x: o.x, y: o.y, width: r.width * zoom, height: r.height * zoom)
    }

    public func toCanvas(_ r: CGRect, deskCenter: CGPoint) -> CGRect {
        let o = toCanvas(r.origin, deskCenter: deskCenter)
        return CGRect(x: o.x, y: o.y, width: r.width / zoom, height: r.height / zoom)
    }
}

public extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
