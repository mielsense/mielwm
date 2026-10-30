import AppKit
import CoreText
import Metal
import MielCore

// CPU drawing for the tags and synthetic windows: a y-down bitmap context,
// the theme (macOS's dark and light materials), SF Pro and app icons.

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [r, g, b, a])!
}

extension CGColor {
    func withAlphaComponent(_ a: Double) -> CGColor { copy(alpha: a) ?? self }
}

/// A rounded rectangle with continuous corners, as macOS draws its own: the
/// curve starts 1.53 radii from the corner and eases into the straight edge
/// instead of meeting it at a circle's tangent. Where there is no room for
/// that (a capsule), the corners are circular.
func continuousRoundedPath(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    let radius = max(0, min(radius, r.width / 2, r.height / 2))
    let k: CGFloat = 1.52866483
    guard radius > 0, radius * k <= min(r.width, r.height) / 2 else {
        return CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
    let p = CGMutablePath()
    // One corner, turning from the edge along `a` to the edge along `b`, `c` its point.
    func corner(_ c: CGPoint, _ a: CGVector, _ b: CGVector) {
        func at(_ u: CGFloat, _ v: CGFloat) -> CGPoint { CGPoint(x: c.x + (a.dx * u + b.dx * v) * radius, y: c.y + (a.dy * u + b.dy * v) * radius) }
        p.addLine(to: at(k, 0))
        p.addCurve(to: at(0.63149399, 0.07491100), control1: at(1.08849296, 0), control2: at(0.86840694, 0))
        p.addCurve(to: at(0.07491100, 0.63149399), control1: at(0.37282392, 0.16905899), control2: at(0.16905899, 0.37282392))
        p.addCurve(to: at(0, k), control1: at(0, 0.86840694), control2: at(0, 1.08849296))
    }
    p.move(to: CGPoint(x: r.minX + radius * k, y: r.minY))
    corner(CGPoint(x: r.maxX, y: r.minY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: 1))
    corner(CGPoint(x: r.maxX, y: r.maxY), CGVector(dx: 0, dy: -1), CGVector(dx: -1, dy: 0))
    corner(CGPoint(x: r.minX, y: r.maxY), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: -1))
    corner(CGPoint(x: r.minX, y: r.minY), CGVector(dx: 0, dy: 1), CGVector(dx: 1, dy: 0))
    p.closeSubpath()
    return p
}

/// Premultiplied BGRA bitmap with a y-down coordinate system, uploaded as a
/// `.bgra8Unorm` texture.
final class Bitmap {
    let ctx: CGContext
    let width: Int
    let height: Int

    init?(width: Int, height: Int) {
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        self.ctx = ctx
        self.width = width
        self.height = height
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setShouldAntialias(true)
        ctx.setAllowsFontSmoothing(false) // smoothing assumes an opaque background
        ctx.setShouldSubpixelPositionFonts(true)
        ctx.interpolationQuality = .high
    }

    func texture(device: MTLDevice) -> MTLTexture? {
        guard let data = ctx.data else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        desc.usage = .shaderRead
        desc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: data, bytesPerRow: ctx.bytesPerRow)
        return texture
    }

    // MARK: - Shapes

    func roundedPath(_ r: CGRect, _ radius: CGFloat) -> CGPath {
        continuousRoundedPath(r, radius)
    }

    func fill(_ path: CGPath, _ color: CGColor) {
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()
    }

    func stroke(_ path: CGPath, _ color: CGColor, width: CGFloat) {
        ctx.addPath(path)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.strokePath()
    }

    func linearGradient(_ path: CGPath, from: CGPoint, to: CGPoint, _ a: CGColor, _ b: CGColor) {
        guard let gradient = CGGradient(colorsSpace: sRGB, colors: [a, b] as CFArray, locations: [0, 1]) else { return }
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    /// Draws an image upright in y-down space, fitted into `r`.
    func draw(_ image: CGImage, in r: CGRect) {
        let fit = min(r.width / CGFloat(image.width), r.height / CGFloat(image.height))
        let w = CGFloat(image.width) * fit, h = CGFloat(image.height) * fit
        ctx.saveGState()
        ctx.translateBy(x: r.minX + (r.width - w) / 2, y: r.minY + (r.height - h) / 2 + h)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.restoreGState()
    }

    // MARK: - Text

    /// Draws a line with its cap height centered on `cy`. Returns its width.
    @discardableResult
    func draw(_ line: CTLine, x: CGFloat, cy: CGFloat, capHeight: CGFloat) -> CGFloat {
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: x, y: cy + capHeight / 2)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
        return lineWidth(line)
    }
}

func lineWidth(_ line: CTLine) -> CGFloat {
    CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
}

// MARK: - Theme

/// Colors after macOS: a panel fill, a hairline edge, and label and
/// secondary text, in dark or light (`look.dark`).
struct Theme {
    let look: Look
    let accent: CGColor
    let accentRGBA: SIMD4<Float> // opaque, for shaders
    let onAccent: CGColor
    let panel: CGColor // opaque; tags set their own alpha
    let panelRGBA: SIMD4<Float> // opaque, for the minimap shader
    let edge: CGColor // hairline around panels
    let text: CGColor // label
    let textDim: CGColor // secondary label
    let markerRGBA: SIMD4<Float> // minimap windows: rgb, alpha
    let lineRGBA: SIMD4<Float> // minimap viewport and glyph: rgb, alpha
    let edgeRGBA: SIMD4<Float>

    init(look: Look) {
        self.look = look
        let a = look.accent
        accent = rgba(a.r, a.g, a.b)
        accentRGBA = SIMD4(Float(a.r), Float(a.g), Float(a.b), 1)
        onAccent = a.wantsDarkText ? rgba(0, 0, 0, 0.85) : rgba(1, 1, 1)
        let contrast = look.increaseContrast ? 2.5 : 1.0 // Increase Contrast: stronger hairlines and secondary text
        if look.dark {
            panel = rgba(30 / 255, 30 / 255, 32 / 255)
            panelRGBA = SIMD4(30 / 255, 30 / 255, 32 / 255, 1)
            edge = rgba(1, 1, 1, 0.1 * contrast)
            text = rgba(1, 1, 1, look.increaseContrast ? 1 : 0.88)
            textDim = rgba(1, 1, 1, look.increaseContrast ? 0.75 : 0.55)
            markerRGBA = SIMD4(1, 1, 1, 0.38)
            lineRGBA = SIMD4(1, 1, 1, 0.8)
            edgeRGBA = SIMD4(1, 1, 1, Float(0.12 * contrast))
        } else {
            panel = rgba(246 / 255, 246 / 255, 248 / 255)
            panelRGBA = SIMD4(246 / 255, 246 / 255, 248 / 255, 1)
            edge = rgba(0, 0, 0, 0.1 * contrast)
            text = rgba(0, 0, 0, look.increaseContrast ? 1 : 0.85)
            textDim = rgba(0, 0, 0, look.increaseContrast ? 0.7 : 0.5)
            markerRGBA = SIMD4(0, 0, 0, 0.28)
            lineRGBA = SIMD4(0, 0, 0, 0.65)
            edgeRGBA = SIMD4(0, 0, 0, Float(0.12 * contrast))
        }
    }
}

// MARK: - Fonts and text

/// The weights canvas text uses.
enum FontWeight: Hashable { case regular, medium, semibold } // semibold: titles

/// How a run of canvas text is set: its size, weight and tracking.
struct TextStyle {
    var size: CGFloat
    var weight: FontWeight = .regular
    var tracking: CGFloat = 0 // extra space after each character, in pixels
}

/// SF Pro, the system UI font, with its tabular digits so numbers do not
/// jiggle as they change. Core Text applies SF's own size-specific tracking.
final class Typesetter {
    private var fonts: [FontKey: CTFont] = [:]

    private struct FontKey: Hashable {
        var size: CGFloat
        var weight: FontWeight
    }

    func font(_ style: TextStyle) -> CTFont {
        let key = FontKey(size: (style.size * 4).rounded() / 4, weight: style.weight)
        if let f = fonts[key] { return f }
        let weight: NSFont.Weight = switch style.weight {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: max(key.size, 1), weight: weight) as CTFont
        fonts[key] = font
        return font
    }

    func capHeight(_ style: TextStyle) -> CGFloat { CTFontGetCapHeight(font(style)) }

    func line(_ text: String, _ style: TextStyle, _ color: CGColor) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font(style),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTKernAttributeName as String): style.tracking,
        ]))
    }

    /// `line` shortened with an ellipsis to fit `maxWidth`.
    func fit(_ line: CTLine, _ maxWidth: CGFloat, _ style: TextStyle, _ color: CGColor) -> CTLine {
        guard maxWidth > 0, lineWidth(line) > maxWidth else { return line }
        return CTLineCreateTruncatedLine(line, Double(maxWidth), .end, self.line("…", style, color)) ?? line
    }
}

// MARK: - App icons

/// App icons for window tags, read once per app and size.
final class IconCache {
    private var icons: [String: CGImage?] = [:]

    func icon(bundleID: String?, px: Int) -> CGImage? {
        guard let bundleID, px > 0 else { return nil }
        let key = "\(bundleID)@\(px)"
        if let cached = icons[key] { return cached }
        var image: CGImage?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            var rect = CGRect(x: 0, y: 0, width: px, height: px)
            image = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }
        icons[key] = image
        return image
    }
}
