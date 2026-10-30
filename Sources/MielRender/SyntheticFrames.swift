import AppKit
import CoreText
import MielCore

// Fake but believable window content, so snapshots and tests work without
// Screen Recording: a title bar with traffic lights, a sidebar, text lines,
// an image block, tinted per app.

public final class SyntheticFrames: WindowFrameSource, @unchecked Sendable {
    private let lock = NSLock()
    private var images: [WindowID: CGImage] = [:]
    private var generations: [WindowID: UInt64] = [:]
    private let scale: CGFloat

    /// Paints every window at its canvas size times `scale`.
    public init(windows: [SceneWindow], scale: CGFloat = 2) {
        self.scale = scale
        update(windows)
    }

    /// Repaints windows that are new or changed size.
    public func update(_ windows: [SceneWindow]) {
        for w in windows {
            let width = Int((w.canvasFrame.width * scale).rounded()), height = Int((w.canvasFrame.height * scale).rounded())
            lock.lock()
            let current = images[w.id]
            lock.unlock()
            if current?.width == width && current?.height == height { continue }
            guard let image = SyntheticFrames.paint(w, width: width, height: height, scale: scale) else { continue }
            lock.lock()
            images[w.id] = image
            generations[w.id, default: 0] += 1
            lock.unlock()
        }
    }

    public func latestFrame(for id: WindowID) -> WindowFrame? {
        lock.lock()
        defer { lock.unlock() }
        return images[id].map { .image($0) }
    }

    public func generation(for id: WindowID) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return generations[id] ?? 0
    }

    // MARK: - Painting

    private enum Kind { case terminal, editor, browser, document }

    private static func kind(_ w: SceneWindow) -> Kind {
        let name = (w.appName + " " + (w.bundleID ?? "")).lowercased()
        if ["terminal", "ghostty", "iterm", "kitty", "alacritty", "wezterm"].contains(where: name.contains) { return .terminal }
        if ["code", "zed", "xcode", "cursor", "nova", "sublime"].contains(where: name.contains) { return .editor }
        if ["safari", "chrome", "firefox", "arc", "brave", "edge", "orion"].contains(where: name.contains) { return .browser }
        return .document
    }

    /// A stable hue per app.
    private static func hue(_ w: SceneWindow) -> Double {
        var h: UInt32 = 2166136261
        for b in (w.bundleID ?? w.appName).utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return Double(h % 360) / 360
    }

    private static func hsb(_ h: Double, _ s: Double, _ b: Double, _ a: Double = 1) -> CGColor {
        NSColor(hue: h, saturation: s, brightness: b, alpha: a).usingColorSpace(.sRGB)!.cgColor
    }

    static func paint(_ w: SceneWindow, width: Int, height: Int, scale: CGFloat) -> CGImage? {
        guard let b = Bitmap(width: width, height: height) else { return nil }
        let ctx = b.ctx
        let s = scale
        let size = CGSize(width: width, height: height)
        let kind = kind(w)
        let hue = hue(w)
        let dark = kind == .terminal || kind == .editor
        let bounds = CGRect(origin: .zero, size: size)
        let radius = 16 * s
        let window = b.roundedPath(bounds, radius)
        ctx.addPath(window)
        ctx.clip()

        let background = dark ? hsb(hue, 0.18, 0.13) : rgba(0.985, 0.985, 0.98)
        b.fill(CGPath(rect: bounds, transform: nil), background)

        // Title bar.
        let bar: CGFloat = 38 * s
        b.fill(CGPath(rect: CGRect(x: 0, y: 0, width: size.width, height: bar), transform: nil),
               dark ? hsb(hue, 0.2, 0.17) : rgba(0.93, 0.93, 0.925))
        b.fill(CGPath(rect: CGRect(x: 0, y: bar - 1 * s, width: size.width, height: 1 * s), transform: nil),
               dark ? rgba(0, 0, 0, 0.5) : rgba(0, 0, 0, 0.09))
        for (i, color) in [rgba(1, 0.37, 0.34), rgba(1, 0.74, 0.18), rgba(0.16, 0.79, 0.25)].enumerated() {
            let d = 12 * s
            b.fill(CGPath(ellipseIn: CGRect(x: (14 + CGFloat(i) * 20) * s, y: bar / 2 - d / 2, width: d, height: d), transform: nil), color)
        }
        let titleFont = NSFont.systemFont(ofSize: 13 * s, weight: .semibold) as CTFont
        let title = CTLineCreateWithAttributedString(NSAttributedString(string: w.title.isEmpty ? w.appName : w.title, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): titleFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): dark ? rgba(0.85, 0.85, 0.87) : rgba(0.2, 0.2, 0.22),
        ]))
        let fitted = CTLineCreateTruncatedLine(title, Double(size.width - 200 * s), .end, nil) ?? title
        b.draw(fitted, x: (size.width - lineWidth(fitted)) / 2, cy: bar / 2, capHeight: CTFontGetCapHeight(titleFont))

        var content = CGRect(x: 0, y: bar, width: size.width, height: size.height - bar)
        var seed = UInt64(w.id.number) &* 0x9E37_79B9_7F4A_7C15 | 1
        func random() -> Double {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Double(seed % 10000) / 10000
        }

        if kind == .browser {
            let toolbar = 44 * s
            b.fill(CGPath(rect: CGRect(x: 0, y: bar, width: size.width, height: toolbar), transform: nil), rgba(0.95, 0.95, 0.945))
            let field = CGRect(x: size.width * 0.22, y: bar + 9 * s, width: size.width * 0.56, height: toolbar - 18 * s)
            b.fill(b.roundedPath(field, field.height / 2), rgba(0.88, 0.88, 0.875))
            b.fill(b.roundedPath(CGRect(x: field.minX + 14 * s, y: field.midY - 3 * s, width: field.width * 0.4, height: 6 * s), 3 * s),
                   rgba(0.6, 0.6, 0.62))
            content = CGRect(x: 0, y: bar + toolbar, width: size.width, height: size.height - bar - toolbar)
            // A hero image and a few paragraphs.
            let hero = CGRect(x: content.minX + 40 * s, y: content.minY + 30 * s, width: content.width - 80 * s, height: min(content.height * 0.38, 260 * s))
            imageBlock(b, hero, hue: hue, s: s)
            var y = hero.maxY + 28 * s
            b.fill(b.roundedPath(CGRect(x: hero.minX, y: y, width: hero.width * 0.55, height: 16 * s), 4 * s), rgba(0.15, 0.15, 0.17))
            y += 36 * s
            while y < content.maxY - 20 * s {
                let w = hero.width * (0.6 + random() * 0.4)
                b.fill(b.roundedPath(CGRect(x: hero.minX, y: y, width: w, height: 8 * s), 4 * s), rgba(0.62, 0.62, 0.64))
                y += 20 * s
            }
            return ctx.makeImage()
        }

        if kind == .terminal {
            let mono = NSFont.monospacedSystemFont(ofSize: 12.5 * s, weight: .regular) as CTFont
            let lines = ["~ ❯ git status", "On branch main", "Your branch is up to date with 'origin/main'.", "",
                         "~ ❯ swift build", "Building for debugging...", "[42/42] Linking mielwm", "Build complete! (3.41s)",
                         "~ ❯ fastfetch", "  OS: macOS 27.0", "  Host: MacBook Pro (M3 Pro)", "  Shell: fish 4.1",
                         "  Display: 3024x1964 @ 120 Hz", "~ ❯ "]
            var y = content.minY + 24 * s
            for (i, text) in lines.enumerated() where y < content.maxY - 10 * s {
                let prompt = text.hasPrefix("~")
                let color = prompt ? hsb(hue, 0.55, 0.95) : (i % 5 == 3 ? rgba(0.55, 0.85, 0.55) : rgba(0.82, 0.84, 0.86))
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): mono,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
                ]))
                b.draw(line, x: 16 * s, cy: y, capHeight: CTFontGetCapHeight(mono))
                y += 19 * s
            }
            b.fill(CGPath(rect: CGRect(x: 16 * s + 28 * s, y: y - 19 * s - 8 * s, width: 8 * s, height: 16 * s), transform: nil),
                   rgba(0.85, 0.85, 0.87))
            return ctx.makeImage()
        }

        // Sidebar.
        let sidebarWidth = min(200 * s, size.width * 0.28)
        b.fill(CGPath(rect: CGRect(x: 0, y: bar, width: sidebarWidth, height: content.height), transform: nil),
               dark ? hsb(hue, 0.22, 0.11) : hsb(hue, 0.06, 0.95))
        var y = bar + 22 * s
        var row = 0
        while y < size.height - 20 * s {
            let active = row == 2
            if active {
                b.fill(b.roundedPath(CGRect(x: 8 * s, y: y - 11 * s, width: sidebarWidth - 16 * s, height: 22 * s), 6 * s),
                       hsb(hue, 0.55, dark ? 0.55 : 0.85, dark ? 0.6 : 0.35))
            }
            b.fill(b.roundedPath(CGRect(x: 18 * s, y: y - 5 * s, width: 10 * s, height: 10 * s), 3 * s), hsb(hue, 0.5, 0.75))
            b.fill(b.roundedPath(CGRect(x: 36 * s, y: y - 3.5 * s, width: (sidebarWidth - 60 * s) * (0.45 + random() * 0.5), height: 7 * s), 3.5 * s),
                   dark ? rgba(0.55, 0.56, 0.6) : rgba(0.45, 0.45, 0.48))
            y += 28 * s
            row += 1
        }

        let x0 = sidebarWidth + 28 * s
        let textWidth = size.width - x0 - 28 * s
        y = bar + 32 * s
        if kind == .editor {
            let palette = [hsb(0.58, 0.5, 0.9), hsb(0.83, 0.45, 0.9), hsb(0.1, 0.55, 0.95), rgba(0.75, 0.77, 0.8), hsb(0.33, 0.45, 0.8)]
            var line = 0
            while y < size.height - 16 * s {
                b.fill(CGPath(rect: CGRect(x: x0 - 22 * s, y: y - 3.5 * s, width: 10 * s, height: 7 * s), transform: nil), rgba(0.35, 0.36, 0.4))
                var x = x0 + CGFloat(line % 4 == 0 ? 0 : (line % 3) * 2) * 10 * s
                for token in 0..<(1 + Int(random() * 5)) {
                    let w = (20 + random() * 90) * s
                    guard x + w < x0 + textWidth else { break }
                    b.fill(b.roundedPath(CGRect(x: x, y: y - 3.5 * s, width: w, height: 7 * s), 3.5 * s), palette[(line + token) % palette.count])
                    x += w + 8 * s
                }
                y += 19 * s
                line += 1
            }
            // The code minimap down the right edge.
            let mapWidth = min(110 * s, size.width * 0.12)
            let map = CGRect(x: size.width - mapWidth, y: bar, width: mapWidth, height: content.height)
            b.fill(CGPath(rect: map, transform: nil), hsb(hue, 0.2, 0.15))
            b.fill(CGPath(rect: CGRect(x: map.minX + 6 * s, y: map.minY + 40 * s, width: mapWidth - 12 * s, height: 120 * s), transform: nil),
                   rgba(1, 1, 1, 0.06))
            var my = map.minY + 10 * s
            var mapLine = 0
            while my < map.maxY - 8 * s {
                let w = (mapWidth - 24 * s) * (0.3 + random() * 0.7)
                b.fill(CGPath(rect: CGRect(x: map.minX + 12 * s, y: my, width: w, height: 2.5 * s), transform: nil),
                       palette[mapLine % palette.count].withAlphaComponent(0.7))
                my += 5 * s
                mapLine += 1
            }
            return ctx.makeImage()
        }

        // Document: a heading, paragraphs and an image block.
        b.fill(b.roundedPath(CGRect(x: x0, y: y, width: textWidth * 0.5, height: 18 * s), 5 * s), rgba(0.14, 0.14, 0.16))
        y += 42 * s
        var paragraph = 0
        while y < size.height - 24 * s {
            if paragraph == 1 && size.height - y > 180 * s {
                let block = CGRect(x: x0, y: y, width: min(textWidth, 420 * s), height: min(150 * s, (size.height - y) * 0.45))
                imageBlock(b, block, hue: hue, s: s)
                y += block.height + 24 * s
            }
            for i in 0..<4 where y < size.height - 24 * s {
                let w = i == 3 ? textWidth * (0.3 + random() * 0.3) : textWidth * (0.85 + random() * 0.15)
                b.fill(b.roundedPath(CGRect(x: x0, y: y, width: w, height: 8 * s), 4 * s), rgba(0.6, 0.6, 0.62))
                y += 18 * s
            }
            y += 16 * s
            paragraph += 1
        }
        return ctx.makeImage()
    }

    /// A soft landscape: sky gradient, sun, two hills.
    private static func imageBlock(_ b: Bitmap, _ r: CGRect, hue: Double, s: CGFloat) {
        let path = b.roundedPath(r, 10 * s)
        b.linearGradient(path, from: CGPoint(x: r.minX, y: r.minY), to: CGPoint(x: r.minX, y: r.maxY),
                         hsb(hue, 0.45, 0.95), hsb((hue + 0.08).truncatingRemainder(dividingBy: 1), 0.6, 0.7))
        b.ctx.saveGState()
        b.ctx.addPath(path)
        b.ctx.clip()
        let sun = r.height * 0.22
        b.fill(CGPath(ellipseIn: CGRect(x: r.minX + r.width * 0.7, y: r.minY + r.height * 0.18, width: sun, height: sun), transform: nil),
               rgba(1, 0.96, 0.85, 0.9))
        for (i, shade) in [0.55, 0.4].enumerated() {
            let hill = CGMutablePath()
            let base = r.minY + r.height * (0.62 + 0.12 * Double(i))
            hill.move(to: CGPoint(x: r.minX, y: r.maxY))
            hill.addLine(to: CGPoint(x: r.minX, y: base))
            hill.addQuadCurve(to: CGPoint(x: r.maxX, y: base + r.height * 0.05),
                              control: CGPoint(x: r.minX + r.width * (i == 0 ? 0.35 : 0.65), y: base - r.height * 0.35))
            hill.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            hill.closeSubpath()
            b.fill(hill, hsb((hue + 0.3).truncatingRemainder(dividingBy: 1), 0.45, shade))
        }
        b.ctx.restoreGState()
    }
}
