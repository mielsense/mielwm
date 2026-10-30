import CoreGraphics
import Foundation

/// An sRGB colour, each channel from 0 to 1.
public struct RGB: Hashable, Codable, Sendable {
    public var r: Double, g: Double, b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    static let mielOrange = RGB(1.0, 0x6B / 255.0, 0x1A / 255.0) // #ff6b1a

    /// Text on this color reads better dark than white: white wins unless the color is very light (WCAG).
    public var wantsDarkText: Bool {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        return (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05) * 1.6
    }
}

/// What floating panels are made of: Liquid Glass, which bends the edges of
/// what is behind it, or the frosted blur of earlier macOS versions.
public enum GlassStyle: String, Hashable, Codable, Sendable, CaseIterable {
    case liquid, frosted
}

/// How the overview looks, from the appearance settings and the system's: the lens, the grid, the colours and the panels.
public struct Look: Hashable, Codable, Sendable {
    // Lens (distortion.*)
    public var lensEnabled = true
    public var lensStrength = 0.14
    public var lensEdgeScale = 1.08
    public var lensFeather = 0.025
    public var lensTransitionPower = 1.0
    public var edgeBlur = 0.0
    public var edgeBlurStart = 0.45
    public var vignette = 0.0
    public var chromatic = 0.0

    // Canvas backdrop
    public var backgroundDim = 0.35
    public var gridEnabled = true
    public var gridSize = 80.0
    public var gridWidth = 1.0
    public var gridOpacity = 0.1
    public var gridDots = true
    public var gridDotSize = 2.5
    public var wallpaperEnabled = true
    public var blur = false
    public var blurStrength = 0.7
    public var parallaxEnabled = true
    public var parallaxStrength = 0.06
    public var parallaxDepth = 0.12

    // Windows on the map
    public var windowRounding = 10.0
    public var windowShadow = true
    public var labels = true
    public var dimUnmatched = 0.7

    // Minimap (canvas.minimap_*)
    public var minimapEnabled = true
    var minimapWidth = 240.0
    var minimapHeight = 150.0
    var minimapMargin = 24.0
    public var minimapOpacity = 0.8

    // HUD (navigator.*). Text is SF Pro at 12, 13, 14, 16, 18 or 24 pt times hudScale.
    public var accent = RGB.mielOrange
    var monoFont = "" // no longer drawn; kept so old configs load
    public var hudScale = 1.0
    var paletteWidth = 680.0
    var paletteTop = 0.1 // fraction of the screen height
    public var paletteRows = 6
    public var rowHeight = 44.0
    var rounding = 8.0 // no longer drawn; kept so old configs load
    var panelOpacity = 0.8 // no longer drawn; kept so old configs load
    /// appearance:glass: every panel the overview and the notices draw.
    public var glass = GlassStyle.liquid
    var uppercase = false // no longer drawn; kept so old configs load
    var letterSpacing = 0.0 // no longer drawn; kept so old configs load
    public var querySize = 24.0
    public var titleSize = 13.0
    public var detailSize = 12.0
    public var cornerSize = 12.0
    public var labelSize = 12.0
    var cornerLabels = false
    public var searchHeight = 56.0
    var searchBorder = 0.0 // no longer drawn; kept so old configs load
    var searchBorderOpacity = 0.85 // no longer drawn
    var searchBorderColor: RGB? = nil // no longer drawn
    var searchGlow = 0.0 // no longer drawn
    /// Dark or light chrome; the app follows the system appearance.
    public var dark = true
    /// The system's accessibility display options (the app sets them, nothing saves them):
    /// cut instead of flying, opaque panels, stronger edges.
    public var reduceMotion = false
    public var reduceTransparency = false
    public var increaseContrast = false
    /// Whether this Mac has Liquid glass (macOS 26 and later); the app sets it.
    public var liquidGlassAvailable = false

    public init() {}

    /// Liquid glass: chosen, available on this Mac, and not turned solid by Reduce Transparency.
    /// Elsewhere a stored "liquid" (a config synced from another Mac) shows as frosted.
    public var liquid: Bool { glass == .liquid && liquidGlassAvailable && !reduceTransparency }
}

/// macOS's accessibility display options that change how the overview looks and moves.
public struct AccessibilityOptions: Hashable, Sendable {
    public var reduceMotion = false
    public var reduceTransparency = false
    public var increaseContrast = false

    public init(reduceMotion: Bool = false, reduceTransparency: Bool = false, increaseContrast: Bool = false) {
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
    }
}
