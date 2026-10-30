// CPU drawing for text and HUD pieces: a y-down bitmap context, the HUD theme
// (macOS's dark and light materials), SF Pro, SF Symbols and app icons.

import AppKit
import CoreText
import Metal
import MielCore

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [r, g, b, a])!
}

extension CGColor {
    func withAlphaComponent(_ a: Double) -> CGColor { copy(alpha: a) ?? self }
}

/// Premultiplied BGRA bitmap with a y-down coordinate system, uploaded as a
/// `.bgra8Unorm` texture.
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

    // MARK: shapes

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

    /// A shadow or glow outside `path` only, so a translucent fill on top
    /// does not darken.
    func outerShadow(_ path: CGPath, blur: CGFloat, dy: CGFloat = 0, color: CGColor) {
        guard blur > 0, color.alpha > 0.001 else { return }
        ctx.saveGState()
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setShadow(offset: CGSize(width: 0, height: -dy), blur: blur, color: color) // CG shadow offsets ignore the flip
        fill(path, rgba(0, 0, 0, 1))
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setBlendMode(.clear)
        fill(path, rgba(0, 0, 0, 1))
        ctx.endTransparencyLayer()
        ctx.restoreGState()
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

    /// Draws an AppKit image (an SF Symbol) upright into `r`.
    func draw(_ image: NSImage, in r: CGRect) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        image.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: text

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

/// Colors after macOS: translucent panels over a blur, a hairline edge, and
/// label, secondary and tertiary text, in dark or light (`look.dark`).
struct Theme {
    let look: Look
    let accent: CGColor
    let accentRGBA: SIMD4<Float> // opaque, for shaders
    let onAccent: CGColor
    let panel: CGColor // over the blurred backdrop
    let panelRGBA: SIMD4<Float> // opaque, for the minimap shader
    let edge: CGColor // hairline around panels
    let separator: CGColor
    let text: CGColor // label
    let textDim: CGColor // secondary label
    let textFaint: CGColor // tertiary label
    let fill: CGColor // keycaps, icon placeholders, switch tracks
    let highlight: CGColor // the switcher's selected tile
    let shadow: CGColor
    let markerRGBA: SIMD4<Float> // minimap windows: rgb, alpha
    let lineRGBA: SIMD4<Float> // minimap viewport and glyph: rgb, alpha
    let edgeRGBA: SIMD4<Float>
    let shadowBlur = 28.0
    let shadowDrop = 8.0

    init(look: Look) {
        self.look = look
        let a = look.accent
        accent = rgba(a.r, a.g, a.b)
        accentRGBA = SIMD4(Float(a.r), Float(a.g), Float(a.b), 1)
        onAccent = a.wantsDarkText ? rgba(0, 0, 0, 0.85) : rgba(1, 1, 1)
        let alpha = look.reduceTransparency ? 1 : min(max(look.panelOpacity, 0), 1)
        let contrast = look.increaseContrast ? 2.5 : 1.0 // Increase Contrast: stronger hairlines and secondary text
        if look.dark {
            panel = rgba(30 / 255, 30 / 255, 32 / 255, alpha)
            panelRGBA = SIMD4(30 / 255, 30 / 255, 32 / 255, 1)
            edge = rgba(1, 1, 1, 0.1 * contrast)
            separator = rgba(1, 1, 1, 0.1 * contrast)
            text = rgba(1, 1, 1, look.increaseContrast ? 1 : 0.88)
            textDim = rgba(1, 1, 1, look.increaseContrast ? 0.75 : 0.55)
            textFaint = rgba(1, 1, 1, look.increaseContrast ? 0.55 : 0.3)
            fill = rgba(1, 1, 1, 0.1)
            highlight = rgba(1, 1, 1, 0.16)
            shadow = rgba(0, 0, 0, 0.4)
            markerRGBA = SIMD4(1, 1, 1, 0.38)
            lineRGBA = SIMD4(1, 1, 1, 0.8)
            edgeRGBA = SIMD4(1, 1, 1, Float(0.12 * contrast))
        } else {
            panel = rgba(246 / 255, 246 / 255, 248 / 255, min(1, alpha + 0.02))
            panelRGBA = SIMD4(246 / 255, 246 / 255, 248 / 255, 1)
            edge = rgba(0, 0, 0, 0.1 * contrast)
            separator = rgba(0, 0, 0, 0.1 * contrast)
            text = rgba(0, 0, 0, look.increaseContrast ? 1 : 0.85)
            textDim = rgba(0, 0, 0, look.increaseContrast ? 0.7 : 0.5)
            textFaint = rgba(0, 0, 0, look.increaseContrast ? 0.5 : 0.26)
            fill = rgba(0, 0, 0, 0.07)
            highlight = rgba(0, 0, 0, 0.1)
            shadow = rgba(0, 0, 0, 0.2)
            markerRGBA = SIMD4(0, 0, 0, 0.28)
            lineRGBA = SIMD4(0, 0, 0, 0.65)
            edgeRGBA = SIMD4(0, 0, 0, Float(0.12 * contrast))
        }
    }

    /// Room around a panel bitmap for its shadow, in px.
    func shadowMargin(_ s: CGFloat) -> CGFloat { ((shadowBlur + shadowDrop) * s).rounded(.up) }
}

// MARK: - Fonts and text

enum FontWeight: Hashable { case regular, medium, semibold } // semibold: titles

struct TextStyle {
    var size: CGFloat
    var weight: FontWeight = .regular
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
        let font = NSFont.monospacedDigitSystemFont(ofSize: max(key.size, 1), weight: [.regular: .regular, .medium: .medium, .semibold: .semibold][style.weight]!) as CTFont
        fonts[key] = font
        return font
    }

    func capHeight(_ style: TextStyle) -> CGFloat { CTFontGetCapHeight(font(style)) }

    struct Run {
        var text: String
        var color: CGColor
        var medium = false
        var underline = false
    }

    func line(_ text: String, _ style: TextStyle, _ color: CGColor) -> CTLine {
        line([Run(text: text, color: color)], style)
    }

    func line(_ runs: [Run], _ style: TextStyle) -> CTLine {
        let out = NSMutableAttributedString()
        for run in runs where !run.text.isEmpty {
            var weighted = style
            if run.medium { weighted.weight = .medium }
            var attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font(weighted),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): run.color,
            ]
            if run.underline {
                attributes[NSAttributedString.Key(kCTUnderlineStyleAttributeName as String)] = CTUnderlineStyle.single.rawValue
            }
            out.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        return CTLineCreateWithAttributedString(out)
    }

    /// `line` shortened with an ellipsis to fit `maxWidth`.
    func fit(_ line: CTLine, _ maxWidth: CGFloat, _ style: TextStyle, _ color: CGColor, start: Bool = false) -> CTLine {
        guard maxWidth > 0, lineWidth(line) > maxWidth else { return line }
        let token = self.line("…", style, color)
        return CTLineCreateTruncatedLine(line, Double(maxWidth), start ? .start : .end, token) ?? line
    }

    /// `text` with `highlights` (character offsets) set in medium weight.
    func highlighted(_ text: String, _ highlights: [Range<Int>], color: CGColor) -> [Run] {
        guard !highlights.isEmpty else { return [Run(text: text, color: color)] }
        var runs: [Run] = []
        for (i, ch) in text.enumerated() {
            let isHit = highlights.contains { $0.contains(i) }
            if let last = runs.last, last.medium == isHit {
                runs[runs.count - 1].text.append(ch)
            } else {
                runs.append(Run(text: String(ch), color: color, medium: isHit))
            }
        }
        return runs
    }
}

// MARK: - App icons

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

    private var symbols: [String: NSImage] = [:]

    /// An SF Symbol at `pointSize` px in one color.
    func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .regular, color: CGColor) -> NSImage? {
        let key = "\(name)@\(pointSize)/\(weight.rawValue)/\(color.components ?? [])"
        if let cached = symbols[key] { return cached }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(cgColor: color) ?? .white]))
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        if symbols.count > 64 { symbols.removeAll() }
        symbols[key] = image
        return image
    }
}
