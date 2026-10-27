// Draws the mielwm app icon and menu bar glyph and writes them to Resources/:
//   AppIcon.png (1024 px), AppIcon.icns, MenuBarIcon.png + MenuBarIcon@2x.png (template: black + alpha).
// The mark: one honeycomb cell ("miel") cut into tiled window panes ("wm"), on a honey tile.
//
//   swift scripts/make-icon.swift
import AppKit

let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources")
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [CGFloat(hex >> 16 & 255) / 255, CGFloat(hex >> 8 & 255) / 255,
                                           CGFloat(hex & 255) / 255, alpha])!
}

// MARK: Geometry (y down)

/// Rounded rect with continuous ("squircle") corners, the curve Apple uses for icons.
func squircle(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    let curve: [(CGFloat, CGFloat)] = [(1.08849296, 0), (0.86840694, 0), (0.63149399, 0.07491100),
                                       (0.37282383, 0.16905956), (0.16905956, 0.37282383), (0.07491100, 0.63149399),
                                       (0, 0.86840694), (0, 1.08849296), (0, 1.52866483)]
    // each corner: its point, the direction along the edge into it, the direction out of it
    let corners: [(CGPoint, CGVector, CGVector)] = [
        (CGPoint(x: r.maxX, y: r.minY), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: 1)),
        (CGPoint(x: r.maxX, y: r.maxY), CGVector(dx: 0, dy: 1), CGVector(dx: -1, dy: 0)),
        (CGPoint(x: r.minX, y: r.maxY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1)),
        (CGPoint(x: r.minX, y: r.minY), CGVector(dx: 0, dy: -1), CGVector(dx: 1, dy: 0)),
    ]
    func at(_ k: Int, _ u: CGFloat, _ v: CGFloat) -> CGPoint {
        let (c, into, out) = corners[k]
        return CGPoint(x: c.x + (out.dx * v - into.dx * u) * radius, y: c.y + (out.dy * v - into.dy * u) * radius)
    }
    let p = CGMutablePath()
    p.move(to: at(3, 0, 1.52866483))
    for k in 0..<4 {
        p.addLine(to: at(k, 1.52866483, 0))
        for i in stride(from: 0, to: curve.count, by: 3) {
            p.addCurve(to: at(k, curve[i + 2].0, curve[i + 2].1), control1: at(k, curve[i].0, curve[i].1),
                       control2: at(k, curve[i + 1].0, curve[i + 1].1))
        }
    }
    p.closeSubpath()
    return p
}

func roundedPolygon(_ v: [CGPoint], _ radius: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: (v[v.count - 1].x + v[0].x) / 2, y: (v[v.count - 1].y + v[0].y) / 2))
    for i in v.indices { p.addArc(tangent1End: v[i], tangent2End: v[(i + 1) % v.count], radius: radius) }
    p.closeSubpath()
    return p
}

/// Flat-top hexagon from its flat top and bottom rows.
func hexagon(cx: CGFloat, top: CGFloat, bottom: CGFloat) -> [CGPoint] {
    let r = (bottom - top) / sqrt(3), cy = (top + bottom) / 2
    return [CGPoint(x: cx + r, y: cy), CGPoint(x: cx + r / 2, y: bottom), CGPoint(x: cx - r / 2, y: bottom),
            CGPoint(x: cx - r, y: cy), CGPoint(x: cx - r / 2, y: top), CGPoint(x: cx + r / 2, y: top)]
}

/// The part of a convex polygon where a·p <= d.
func clip(_ poly: [CGPoint], _ a: CGVector, _ d: CGFloat) -> [CGPoint] {
    func f(_ p: CGPoint) -> CGFloat { a.dx * p.x + a.dy * p.y - d }
    var out: [CGPoint] = []
    for i in poly.indices {
        let p = poly[i], q = poly[(i + 1) % poly.count]
        if f(p) <= 0 { out.append(p) }
        if f(p) * f(q) < 0 {
            let t = f(p) / (f(p) - f(q))
            out.append(CGPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t))
        }
    }
    return out
}

/// The hexagon cut like a tiling layout: one tall pane on the left, two stacked on the right.
func panes(_ hex: [CGPoint], cx: CGFloat, cy: CGFloat, gap: CGFloat) -> [[CGPoint]] {
    let left = clip(hex, CGVector(dx: 1, dy: 0), cx - gap / 2)
    let right = clip(hex, CGVector(dx: -1, dy: 0), -(cx + gap / 2))
    return [left, clip(right, CGVector(dx: 0, dy: 1), cy - gap / 2), clip(right, CGVector(dx: 0, dy: -1), -(cy + gap / 2))]
}

// MARK: Drawing

func bitmap(_ px: Int) -> CGContext {
    let c = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.translateBy(x: 0, y: CGFloat(px))
    c.scaleBy(x: 1, y: -1)
    return c
}

func writePNG(_ image: CGImage, _ url: URL, dpi: Int = 72) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
    precondition(CGImageDestinationFinalize(dest), "could not write \(url.path)")
}

extension CGContext {
    func fill(_ path: CGPath, _ colors: [CGColor], from: CGFloat, to: CGFloat) {
        saveGState(); addPath(path); clip()
        drawLinearGradient(CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: nil)!,
                           start: CGPoint(x: 0, y: from), end: CGPoint(x: 0, y: to),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        restoreGState()
    }

    /// Draws `body` with a drop shadow; shadows ignore the CTM, so `scale` converts to pixels.
    func withShadow(_ color: CGColor, blur: CGFloat, dy: CGFloat, scale: CGFloat, _ body: () -> Void) {
        saveGState()
        setShadow(offset: CGSize(width: 0, height: -dy * scale), blur: blur * scale, color: color)
        beginTransparencyLayer(auxiliaryInfo: nil); body(); endTransparencyLayer()
        restoreGState()
    }

    /// Soft shade along the inside edge of `path`, pushed down by `dy`: the shadow of a ring around it.
    /// The ring itself is drawn far off to the side so its anti-aliased edge never shows.
    func innerShade(_ path: CGPath, _ color: CGColor, blur: CGFloat, dy: CGFloat, scale: CGFloat) {
        let away: CGFloat = 4000
        saveGState(); addPath(path); clip()
        let ring = CGMutablePath()
        ring.addRect(path.boundingBox.insetBy(dx: -400, dy: -400))
        ring.addPath(path)
        setShadow(offset: CGSize(width: -away * scale, height: -dy * scale), blur: blur * scale, color: color)
        translateBy(x: away, y: 0)
        addPath(ring); setFillColor(rgb(0)); fillPath(using: .evenOdd)
        restoreGState()
    }
}

/// The app icon at `px` pixels, drawn on Apple's 1024 grid: an 824 body at a 100 inset.
func appIcon(_ px: Int) -> CGImage {
    let c = bitmap(px)
    let s = CGFloat(px) / 1024
    c.scaleBy(x: s, y: s)
    let small = px <= 32 // the 32 px image (16 pt @2x): no texture or shading, gaps wide enough to stay open
    let body = squircle(CGRect(x: 100, y: 100, width: 824, height: 824), 214) // 214: fitted to macOS 26+ icons

    // drawn as one layer so its shadow (the one macOS gives its own icons, measured) has no seam at the edge;
    // macOS 26+ redraws that shadow and adds its glass edge itself
    c.withShadow(rgb(0, 0.25), blur: 30, dy: 8, scale: s) {
        c.addPath(body); c.clip()
        c.fill(body, [rgb(0xFFD35C), rgb(0xFBB031), rgb(0xF08A0C)], from: 100, to: 924)
        c.drawRadialGradient(CGGradient(colorsSpace: sRGB, colors: [rgb(0xFFF2C4, 0.5), rgb(0xFFF2C4, 0)] as CFArray, locations: nil)!,
                             startCenter: CGPoint(x: 330, y: 200), startRadius: 0, endCenter: CGPoint(x: 330, y: 200),
                             endRadius: 560, options: [])
        if !small { // the canvas: a faint honeycomb that runs off the edges
            let comb = CGMutablePath()
            let r: CGFloat = 64, w = 1.5 * r, h = sqrt(3) * r
            for i in -6...6 { for j in -5...5 {
                let x = 512 + CGFloat(i) * w, y = 512 + CGFloat(j) * h + (i & 1 == 0 ? 0 : h / 2)
                comb.addPath(roundedPolygon(hexagon(cx: x, top: y - h / 2, bottom: y + h / 2), 5))
            } }
            c.addPath(comb); c.setStrokeColor(rgb(0xB85E00, 0.07)); c.setLineWidth(4); c.strokePath()
        }

        let cx: CGFloat = 512, cy: CGFloat = 512, hexHeight: CGFloat = 520
        let hex = hexagon(cx: cx, top: cy - hexHeight / 2, bottom: cy + hexHeight / 2)
        for poly in panes(hex, cx: cx, cy: cy, gap: small ? 64 : 32) {
            let pane = roundedPolygon(poly, 34)
            let box = pane.boundingBox
            c.withShadow(rgb(0x7A3A00, 0.38), blur: 36, dy: 16, scale: s) { c.addPath(pane); c.setFillColor(rgb(0xFFFFFF)); c.fillPath() }
            c.fill(pane, [rgb(0xFFFFFF), rgb(0xFFF6E8)], from: box.minY, to: box.maxY)
            guard !small else { continue }
            c.innerShade(pane, rgb(0xC8741A, 0.22), blur: 10, dy: -4, scale: s)
            if px >= 128 { // title-bar dots along the pane's top edge
                let top = poly.map(\.y).min()!
                let left = poly.filter { abs($0.y - top) < 0.5 }.map(\.x).min()!
                c.setFillColor(rgb(0xE9A23B, 0.75))
                for k in 0..<3 { c.fillEllipse(in: CGRect(x: left + 34 + CGFloat(k) * 30, y: top + 30, width: 18, height: 18)) }
            }
        }
    }
    return c.makeImage()!
}

/// The menu bar glyph: the mark as an outline, 18 pt square, strokes on whole pixels at each scale.
func menuBarIcon(scale: Int) -> CGImage {
    let c = bitmap(18 * scale)
    let line: CGFloat = scale == 1 ? 1 : 3
    // stroke centers: the flat edges and both dividers land on pixel centers (x.5) so they stay crisp
    let (top, bottom, cx, divider): (CGFloat, CGFloat, CGFloat, CGFloat) = scale == 1 ? (2.5, 16.5, 9, 8.5) : (5.5, 31.5, 18, 17.5)
    let hex = hexagon(cx: cx, top: top, bottom: bottom)
    c.setStrokeColor(rgb(0)); c.setLineWidth(line); c.setLineJoin(.round)
    c.addPath(roundedPolygon(hex, scale == 1 ? 1.5 : 3)); c.strokePath()
    let cy = (top + bottom) / 2
    c.move(to: CGPoint(x: divider, y: top)); c.addLine(to: CGPoint(x: divider, y: bottom))
    c.move(to: CGPoint(x: divider, y: cy)); c.addLine(to: hex[0])
    c.strokePath()
    return c.makeImage()!
}

// MARK: Output

let fm = FileManager.default
try fm.createDirectory(at: resources, withIntermediateDirectories: true)
let iconset = fm.temporaryDirectory.appendingPathComponent("mielwm-\(getpid()).iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: iconset) }

// macOS 26+ shows 16 and 32 px images from an .icns in a grey tile, whatever they look like (even Apple's
// own pixels), so the set leaves them out and macOS scales the @2x ones down instead.
for (points, scales) in [(16, [2]), (32, [2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        writePNG(appIcon(points * scale), iconset.appendingPathComponent("icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"),
                 dpi: 72 * scale)
    }
}
writePNG(appIcon(1024), resources.appendingPathComponent("AppIcon.png"))
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
precondition(iconutil.terminationStatus == 0, "iconutil failed")

writePNG(menuBarIcon(scale: 1), resources.appendingPathComponent("MenuBarIcon.png"))
writePNG(menuBarIcon(scale: 2), resources.appendingPathComponent("MenuBarIcon@2x.png"), dpi: 144)
print("wrote AppIcon.png, AppIcon.icns, MenuBarIcon.png, MenuBarIcon@2x.png to \(resources.path)")
