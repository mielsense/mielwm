import CoreGraphics

/// How a key cap is drawn, in points at 13 pt text, for every surface that
/// draws one: Settings, the overview's HUD, the notices and the canvas.
/// Each scales the lengths with its text size. DESIGN.md explains the recipe.
public enum KeyCapMetrics {
    public static let textSize: CGFloat = 13
    public static let tracking: CGFloat = 1
    public static let radius: CGFloat = 6
    public static let paddingAcross: CGFloat = 8
    public static let paddingDown: CGFloat = 3
    public static let minHeight: CGFloat = 22
    /// The text: the primary colour at this opacity.
    public static let textOpacity = 0.85
    /// The fill: the primary colour at rest and on hover, on a window or a solid panel.
    public static let rest = 0.05, hover = 0.09
    /// The fill on Liquid glass or frosted panels, where 5% disappears against the backdrop.
    public static let onGlass = 0.12
    /// The fill on a selected row's accent: white at this opacity, under the accent's text colour.
    public static let onAccent = 0.22
}
