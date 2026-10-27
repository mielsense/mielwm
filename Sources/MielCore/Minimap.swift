import CoreGraphics

/// Where the minimap and its arrange button sit on one screen and how canvas
/// points map into it. Screen-local points, top-left origin, not lensed (the
/// minimap is composed after the lens). Same numbers as Phantomat
/// renderCanvasMinimap / jumpCanvasMinimap / canvasArrangeButtonBox, in points
/// instead of device pixels and without their pixel rounding.
public struct MinimapLayout: Hashable, Sendable {
    public var panel: CGRect
    public var arrangeButton: CGRect
    public var content: CGRect // panel inset by 12
    public var worldBounds: CGRect // the canvas rect the panel shows
    public var fit: CGFloat // panel points per canvas point
    public var origin: CGPoint // where worldBounds.origin lands
    public var windows: [CGRect] // markers, same order as the input
    public var workspaces: [CGRect] = [] // workspace outlines, same order as the input
    public var viewport: CGRect // the viewport marker

    public enum Hit: Hashable, Sendable {
        case arrange
        case jump(CGPoint) // canvas point to center the camera on
    }

    public func toPanel(_ canvasPoint: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + (canvasPoint.x - worldBounds.minX) * fit,
                y: origin.y + (canvasPoint.y - worldBounds.minY) * fit)
    }

    public func toCanvas(_ panelPoint: CGPoint) -> CGPoint {
        let f = max(fit, 0.0001)
        return CGPoint(x: worldBounds.minX + (panelPoint.x - origin.x) / f,
                       y: worldBounds.minY + (panelPoint.y - origin.y) / f)
    }

    /// What a click at `point` does: the arrange button wins over the panel.
    public func hit(_ point: CGPoint) -> Hit? {
        if arrangeButton.contains(point) { return .arrange }
        return panel.contains(point) ? .jump(toCanvas(point)) : nil
    }

    func marker(_ canvasRect: CGRect) -> CGRect {
        let o = toPanel(canvasRect.origin)
        return CGRect(x: o.x, y: o.y, width: max(2, canvasRect.width * fit), height: max(2, canvasRect.height * fit))
    }
}

/// Minimap for one screen. `windows` are canvas frames (pinned windows left
/// out), `viewport` is the canvas rect the screen shows, `workspaces` the
/// workspaces' frames.
public func minimapLayout(screenSize: CGSize, look: Look, windows: [CGRect], viewport: CGRect,
                          workspaces: [CGRect] = []) -> MinimapLayout {
    let width = look.minimapWidth, height = look.minimapHeight, margin = look.minimapMargin
    let panel = CGRect(x: screenSize.width - margin - width, y: screenSize.height - margin - height,
                       width: width, height: height)
    let button = CGRect(x: panel.minX - 8 - 36, y: panel.maxY - 36, width: 36, height: 36)
    let inset = 12.0
    let content = CGRect(x: panel.minX + inset, y: panel.minY + inset,
                         width: max(1, panel.width - inset * 2), height: max(1, panel.height - inset * 2))

    var bounds = (windows + workspaces).filter { $0.width > 0 && $0.height > 0 }.reduce(viewport) { $0.union($1) }
    let padding = max(80, max(bounds.width, bounds.height) * 0.06)
    bounds = bounds.insetBy(dx: -padding, dy: -padding)

    let fit = min(content.width / max(bounds.width, 1), content.height / max(bounds.height, 1))
    let origin = CGPoint(x: content.minX + (content.width - bounds.width * fit) / 2,
                         y: content.minY + (content.height - bounds.height * fit) / 2)
    var layout = MinimapLayout(panel: panel, arrangeButton: button, content: content, worldBounds: bounds,
                               fit: fit, origin: origin, windows: [], viewport: .zero)
    layout.windows = windows.map(layout.marker)
    layout.workspaces = workspaces.map(layout.marker)
    layout.viewport = layout.marker(viewport)
    return layout
}
