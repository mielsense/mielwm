// The HUD, rasterized with Core Text into textures that are composited after
// the lens, so text is never bent. It looks like macOS's own overlays
// (Spotlight, the app switcher, the volume HUD): SF Pro at 12-24 pt, panels
// over a blur, keycaps for keys. Every length is in device pixels (`s` =
// backing scale × hud scale); the palette's metrics are Core's PaletteMetrics.

import AppKit
import CoreText
import Metal
import MielCore

/// One rasterized HUD piece and where it sits on the screen, in px.
struct HUDLayer {
    var key: Int
    var texture: MTLTexture
    var rect: CGRect
    var caret: CGRect? // layer-local; blinked by the shader
    var panel: CGRect? // layer-local; the renderer blurs what is behind it
    var radius: CGFloat = 0
}

/// What the painter needs to know about the screen, all in px.
struct HUDView {
    var size: CGSize
    var scale: CGFloat // backing scale
    var topInset: CGFloat // notch or menu bar
    var bottomInset: CGFloat // Dock
    var minimapTop: CGFloat? // the minimap panel's top edge, when shown
}

final class HUDPainter {
    let device: MTLDevice
    let type = Typesetter()
    let icons = IconCache()

    init(device: MTLDevice) {
        self.device = device
    }

    private func layer(_ bitmap: Bitmap?, key: Int, at origin: CGPoint, caret: CGRect? = nil,
                       panel: CGRect? = nil, radius: CGFloat = 0) -> HUDLayer? {
        guard let bitmap, let texture = bitmap.texture(device: device) else { return nil }
        return HUDLayer(key: key, texture: texture,
                        rect: CGRect(x: origin.x, y: origin.y, width: CGFloat(bitmap.width), height: CGFloat(bitmap.height)),
                        caret: caret, panel: panel, radius: radius)
    }

    // MARK: - Shared pieces

    /// Draws `string` vertically centered on `cy`, ellipsized to `maxWidth`. Returns its width.
    @discardableResult
    private func text(_ b: Bitmap, _ runs: [Typesetter.Run], _ style: TextStyle, x: CGFloat, cy: CGFloat,
                      maxWidth: CGFloat = 0, start: Bool = false) -> CGFloat {
        guard !runs.isEmpty else { return 0 }
        var line = type.line(runs, style)
        if maxWidth > 0 { line = type.fit(line, maxWidth, style, runs.last!.color, start: start) }
        return b.draw(line, x: x, cy: cy, capHeight: type.capHeight(style))
    }

    @discardableResult
    private func text(_ b: Bitmap, _ string: String, _ style: TextStyle, _ color: CGColor, x: CGFloat, cy: CGFloat,
                      maxWidth: CGFloat = 0) -> CGFloat {
        text(b, [Typesetter.Run(text: string, color: color)], style, x: x, cy: cy, maxWidth: maxWidth)
    }

    private func measure(_ string: String, _ style: TextStyle) -> CGFloat {
        lineWidth(type.line(string, style, rgba(1, 1, 1)))
    }

    /// A panel: a soft shadow, the translucent material tint and a hairline.
    /// `opaque` for pieces shown over the live desktop, where nothing behind
    /// can be blurred and window text must not show through.
    private func panel(_ b: Bitmap, _ r: CGRect, _ radius: CGFloat, _ s: CGFloat, _ theme: Theme, opaque: Bool = false) {
        let path = b.roundedPath(r, radius)
        b.outerShadow(path, blur: theme.shadowBlur * s, dy: theme.shadowDrop * s, color: theme.shadow)
        b.fill(path, opaque ? theme.panel.withAlphaComponent(1) : theme.panel)
        if theme.look.liquid { glassLight(b, r, radius, s, theme, sheen: opaque) }
        b.stroke(b.roundedPath(r.insetBy(dx: 0.5, dy: 0.5), radius - 0.5), theme.edge, width: 1)
    }

    /// Liquid glass's light: a rim lit from above, brightest along the top and
    /// a little again at the bottom, where light leaves the glass. `sheen`
    /// adds a soft glow inside the top, for panels with nothing behind them to bend.
    func glassLight(_ b: Bitmap, _ r: CGRect, _ radius: CGFloat, _ s: CGFloat, _ theme: Theme, sheen: Bool = false) {
        let dark = theme.look.dark
        let ctx = b.ctx
        func gradient(_ stops: [(CGFloat, CGFloat)]) -> CGGradient? {
            CGGradient(colorsSpace: sRGB, colors: stops.map { rgba(1, 1, 1, $0.1) } as CFArray, locations: stops.map(\.0))
        }
        ctx.saveGState()
        let ring = CGMutablePath()
        ring.addPath(b.roundedPath(r, radius))
        ring.addPath(b.roundedPath(r.insetBy(dx: 1.5 * s, dy: 1.5 * s), max(0, radius - 1.5 * s)))
        ctx.addPath(ring)
        ctx.clip(using: .evenOdd)
        if let g = gradient(dark ? [(0, 0.5), (0.35, 0.1), (0.8, 0.06), (1, 0.22)] : [(0, 1), (0.35, 0.5), (0.8, 0.35), (1, 0.8)]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: r.minY), end: CGPoint(x: 0, y: r.maxY), options: [])
        }
        ctx.restoreGState()
        guard sheen else { return }
        ctx.saveGState()
        ctx.addPath(b.roundedPath(r, radius))
        ctx.clip()
        if let g = gradient([(0, dark ? 0.08 : 0.5), (1, 0)]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: r.minY), end: CGPoint(x: 0, y: r.minY + min(r.height * 0.5, 60 * s)), options: [])
        }
        ctx.restoreGState()
    }

    private func hairline(_ b: Bitmap, x: CGFloat, y: CGFloat, width: CGFloat, _ theme: Theme) {
        b.ctx.setFillColor(theme.separator)
        b.ctx.fill(CGRect(x: x, y: y.rounded(), width: width, height: 1))
    }

    // MARK: keycaps

    private func keycapStyle(_ size: CGFloat) -> TextStyle { TextStyle(size: size, weight: .medium) }

    private func keycapWidth(_ key: String, _ style: TextStyle) -> CGFloat {
        max(measure(key, style) + style.size * 0.84, (style.size * 1.6).rounded())
    }

    /// One key as a light capsule behind its glyphs. Returns its width.
    @discardableResult
    private func keycap(_ b: Bitmap, _ key: String, _ style: TextStyle, x: CGFloat, cy: CGFloat, onAccent: Bool, _ theme: Theme) -> CGFloat {
        let w = keycapWidth(key, style), h = (style.size * 1.6).rounded()
        let box = CGRect(x: x, y: (cy - h / 2).rounded(), width: w, height: h)
        b.fill(b.roundedPath(box, h / 2), onAccent ? rgba(1, 1, 1, 0.22) : theme.fill)
        let color = onAccent ? theme.onAccent : theme.textDim
        let tw = measure(key, style)
        text(b, key, style, color, x: box.midX - tw / 2, cy: cy)
        return w
    }

    /// "{⌃0} Fit all  {⎋} Back": keycaps and labels. Draws when `b` is
    /// given; returns the width either way.
    @discardableResult
    private func hints(_ b: Bitmap?, _ hint: String, _ style: TextStyle, x: CGFloat, cy: CGFloat, s: CGFloat, _ theme: Theme,
                       color: CGColor? = nil) -> CGFloat {
        let caps = keycapStyle(style.size)
        var cx = x, previousKey: Bool?
        for segment in hintSegments(hint) {
            let piece = segment.text.trimmingCharacters(in: .whitespaces)
            guard !piece.isEmpty else { continue }
            if let previousKey { cx += previousKey && !segment.isKey ? 5 * s : previousKey && segment.isKey ? 3 * s : 14 * s }
            if segment.isKey {
                cx += b.map { keycap($0, piece, caps, x: cx, cy: cy, onAccent: false, theme) } ?? keycapWidth(piece, caps)
            } else {
                if let b { text(b, piece, style, color ?? theme.textDim, x: cx, cy: cy) }
                cx += measure(piece, style)
            }
            previousKey = segment.isKey
        }
        return cx - x
    }

    /// Help sheet keys: space-separated keycaps; plain words (Click, drag) as text.
    private func keyTokens(_ keys: String) -> [(text: String, isKey: Bool)] {
        var out: [(text: String, isKey: Bool)] = []
        for token in keys.split(separator: " ").map(String.init) {
            let isKey = token.count == 1 || ["Space", "esc"].contains(token) || token.contains { !$0.isLetter }
            if !isKey, let last = out.last, !last.isKey { out[out.count - 1].text += " " + token } else { out.append((token, isKey)) }
        }
        return out
    }

    @discardableResult
    private func keys(_ b: Bitmap?, _ keys: String, _ style: TextStyle, right: CGFloat, cy: CGFloat, s: CGFloat, _ theme: Theme) -> CGFloat {
        let caps = keycapStyle(style.size)
        let tokens = keyTokens(keys)
        let widths = tokens.map { $0.isKey ? keycapWidth($0.text, caps) : measure($0.text, style) }
        let total = widths.reduce(0, +) + CGFloat(max(tokens.count - 1, 0)) * 4 * s
        guard let b else { return total }
        var x = right - total
        for (token, w) in zip(tokens, widths) {
            if token.isKey { keycap(b, token.text, caps, x: x, cy: cy, onAccent: false, theme) } else { text(b, token.text, style, theme.textDim, x: x, cy: cy) }
            x += w + 4 * s
        }
        return total
    }

    // MARK: icons

    private func appIcon(_ b: Bitmap, _ r: CGRect, bundleID: String?, fallback: String, _ theme: Theme) {
        if let icon = icons.icon(bundleID: bundleID, px: Int(r.width.rounded())) {
            b.draw(icon, in: r)
            return
        }
        b.fill(b.roundedPath(r.insetBy(dx: r.width * 0.08, dy: r.width * 0.08), r.width * 0.22), theme.fill)
        let code = String(fallback.filter { $0.isLetter || $0.isNumber }.prefix(2))
        let style = TextStyle(size: max(12, r.width * 0.36), weight: .medium)
        text(b, code, style, theme.textDim, x: r.midX - measure(code, style) / 2, cy: r.midY)
    }

    // MARK: - Search and help: the palette

    func palette(_ hud: HUDModel, _ theme: Theme, _ view: HUDView, key: Int) -> HUDLayer? {
        let look = theme.look
        let s = view.scale * look.hudScale
        let m = theme.shadowMargin(s)
        let help = hud.mode == .help
        let list = hud.mode == .search && (!hud.rows.isEmpty || !hud.query.isEmpty)
        let columns = help ? 3 : 1
        let width = min((help ? max(look.paletteWidth, 960) : look.paletteWidth) * s, view.size.width * 0.94)
        let inset = PaletteMetrics.listInset * s
        let radius = (look.rounding + PaletteMetrics.panelExtraRadius) * s
        let count = min(hud.rows.count, max(1, look.paletteRows))
        let rowHeight = look.rowHeight * s
        let selected = hud.selectedRow ?? -1
        let rows = list ? max(1, count) : 0 // Core already sends only the visible rows
        let showFooter = list && !hud.footer.isEmpty
        let footHeight = PaletteMetrics.footerHeight * s
        let sections = help ? helpColumns(hud.help, count: columns) : []
        let helpHeight = help ? self.helpHeight(sections, s: s) : 0
        let fieldHeight = look.searchHeight * s

        var height = fieldHeight
        if rows > 0 { height += inset * 2 + CGFloat(rows) * rowHeight + (showFooter ? footHeight : 0) }
        if help { height += helpHeight }

        guard let b = Bitmap(width: Int(ceil(width + m * 2)), height: Int(ceil(height + m * 2))) else { return nil }
        let box = CGRect(x: m, y: m, width: width, height: height)
        panel(b, box, radius, s, theme)
        let caret = searchField(b, CGRect(x: m, y: m, width: width, height: fieldHeight), s: s, hud: hud, theme)
        var y = m + fieldHeight
        if rows > 0 || help { hairline(b, x: m, y: y, width: width, theme) }

        if rows > 0 {
            y += inset
            let x = m + inset, rowWidth = width - inset * 2
            if hud.rows.isEmpty {
                let r = CGRect(x: x, y: y, width: rowWidth, height: rowHeight)
                let title = TextStyle(size: look.titleSize * s)
                let message = "No windows match \"\(hud.query)\""
                text(b, message, title, theme.textDim, x: r.minX + 12 * s, cy: r.midY, maxWidth: rowWidth - 24 * s)
            }
            for row in 0..<count {
                let r = CGRect(x: x, y: y + CGFloat(row) * rowHeight, width: rowWidth, height: rowHeight)
                searchRow(b, hud.rows[row], r, s: s, selected: row == selected, theme)
            }
            y += CGFloat(rows) * rowHeight + inset
            if showFooter {
                hairline(b, x: m, y: y, width: width, theme)
                let style = TextStyle(size: look.detailSize * s)
                text(b, hud.footer, style, theme.textFaint, x: m + 16 * s, cy: y + footHeight / 2,
                     maxWidth: width - 32 * s)
            }
        }

        if help {
            drawHelp(b, sections, CGRect(x: m, y: y, width: width, height: helpHeight), s: s, theme)
        }

        let top = PaletteMetrics.top(look, screenHeight: view.size.height / view.scale, topInset: view.topInset / view.scale) * view.scale
        return layer(b, key: key, at: CGPoint(x: ((view.size.width - CGFloat(b.width)) / 2).rounded(), y: (top - m).rounded()),
                     caret: caret, panel: box, radius: radius)
    }

    /// Spotlight's field: a magnifying glass and the query in the biggest
    /// size, the placeholder in the tertiary color. Returns the caret rect.
    private func searchField(_ b: Bitmap, _ r: CGRect, s: CGFloat, hud: HUDModel, _ theme: Theme) -> CGRect {
        let look = theme.look
        let size = look.querySize * s
        let style = TextStyle(size: size)
        let glyph = (size * 0.8).rounded()
        let gx = r.minX + 18 * s
        if let image = icons.symbol("magnifyingglass", pointSize: glyph, color: theme.textDim) {
            let fit = min(glyph * 1.3 / max(image.size.width, 1), glyph * 1.3 / max(image.size.height, 1), 1)
            let w = image.size.width * fit, h = image.size.height * fit
            b.draw(image, in: CGRect(x: gx + (glyph - w) / 2, y: r.midY - h / 2, width: w, height: h))
        }
        let textX = gx + glyph + 12 * s
        let textMax = r.maxX - textX - 18 * s
        let caretHeight = (size * 1.15).rounded()
        var caretX = textX
        if hud.query.isEmpty && hud.markedText.isEmpty {
            text(b, hud.placeholder, style, theme.textFaint, x: textX + 4 * s, cy: r.midY, maxWidth: textMax)
        } else {
            let runs = [Typesetter.Run(text: hud.query, color: theme.text),
                        Typesetter.Run(text: hud.markedText, color: theme.text, underline: true)]
            caretX = textX + min(text(b, runs, style, x: textX, cy: r.midY, maxWidth: textMax, start: true), textMax) + 1 * s
        }
        return CGRect(x: caretX.rounded(), y: (r.midY - caretHeight / 2).rounded(), width: max(2, (1.5 * s).rounded()), height: caretHeight)
    }

    private func searchRow(_ b: Bitmap, _ row: HUDRow, _ r: CGRect, s: CGFloat, selected: Bool, _ theme: Theme) {
        let look = theme.look
        if selected { b.fill(b.roundedPath(r, look.rounding * s), theme.accent) }
        let icon = (min(r.height * 0.66, 48 * s)).rounded()
        appIcon(b, CGRect(x: r.minX + 8 * s, y: (r.midY - icon / 2).rounded(), width: icon, height: icon), bundleID: row.bundleID,
                fallback: row.detail.isEmpty ? row.title : row.detail, theme)

        var right = r.maxX - 10 * s
        if !row.trailing.isEmpty {
            let caps = keycapStyle(look.detailSize * s)
            let w = keycapWidth(row.trailing, caps)
            keycap(b, row.trailing, caps, x: right - w, cy: r.midY, onAccent: selected, theme)
            right -= w + 12 * s
        }

        let tx = r.minX + 8 * s + icon + 10 * s
        let maxWidth = right - tx
        let titleStyle = TextStyle(size: look.titleSize * s), detailStyle = TextStyle(size: look.detailSize * s)
        let titleHeight = look.titleSize * 1.2 * s, detailHeight = look.detailSize * 1.2 * s
        let total = titleHeight + (row.detail.isEmpty ? 0 : detailHeight + 1 * s)
        let titleY = r.midY - total / 2 + titleHeight / 2
        let color = selected ? theme.onAccent : theme.text
        text(b, type.highlighted(row.title, row.highlights, color: color), titleStyle, x: tx, cy: titleY, maxWidth: maxWidth)
        if !row.detail.isEmpty {
            text(b, row.detail, detailStyle, selected ? theme.onAccent.withAlphaComponent(0.8) : theme.textDim,
                 x: tx, cy: r.midY + total / 2 - detailHeight / 2, maxWidth: maxWidth)
        }
    }

    // MARK: help

    // Help sheet spacing in points: the title band, a section header, a row, the gap between sections.
    private static let helpTitle = 52.0, helpHeader = 28.0, helpLine = 24.0, helpSectionGap = 14.0

    private func sectionHeight(_ section: HelpSection) -> Double {
        Self.helpHeader + Double(section.entries.count) * Self.helpLine + Self.helpSectionGap
    }

    /// Sections split into `count` columns of about equal height, in order.
    private func helpColumns(_ sections: [HelpSection], count: Int) -> [[HelpSection]] {
        let heights = sections.map(sectionHeight)
        let target = heights.reduce(0, +) / Double(max(count, 1))
        var columns: [[HelpSection]] = [[]]
        var acc = 0.0
        for (section, h) in zip(sections, heights) {
            if !columns[columns.count - 1].isEmpty, columns.count < count, acc + h / 2 > target * Double(columns.count) { columns.append([]) }
            columns[columns.count - 1].append(section)
            acc += h
        }
        return columns
    }

    private func helpHeight(_ columns: [[HelpSection]], s: CGFloat) -> CGFloat {
        let tallest = columns.map { $0.map(sectionHeight).reduce(0, +) }.max() ?? 0
        return (Self.helpTitle + tallest + 6) * s
    }

    /// A macOS keyboard-shortcuts sheet: a title, then columns of sections,
    /// each row "Action … keycaps".
    private func drawHelp(_ b: Bitmap, _ columns: [[HelpSection]], _ r: CGRect, s: CGFloat, _ theme: Theme) {
        let title = TextStyle(size: 18 * s, weight: .semibold)
        let header = TextStyle(size: 13 * s, weight: .semibold)
        let row = TextStyle(size: 13 * s)
        let keyStyle = TextStyle(size: 11 * s)
        let pad = 24 * s, columnGap = 28 * s
        text(b, "Shortcuts", title, theme.text, x: r.minX + pad, cy: r.minY + Self.helpTitle / 2 * s + 2 * s)
        let n = CGFloat(max(columns.count, 1))
        let columnWidth = (r.width - pad * 2 - columnGap * (n - 1)) / n
        for (i, sections) in columns.enumerated() {
            let x = r.minX + pad + CGFloat(i) * (columnWidth + columnGap)
            var y = r.minY + Self.helpTitle * s
            for section in sections {
                text(b, section.title, header, theme.textDim, x: x, cy: y + Self.helpHeader / 2 * s, maxWidth: columnWidth)
                y += Self.helpHeader * s
                for entry in section.entries {
                    let cy = y + Self.helpLine / 2 * s
                    let keysWidth = keys(b, entry.keys, keyStyle, right: x + columnWidth, cy: cy, s: s, theme)
                    text(b, entry.action, row, theme.text, x: x, cy: cy, maxWidth: columnWidth - keysWidth - 10 * s)
                    y += Self.helpLine * s
                }
                y += Self.helpSectionGap * s
            }
        }
    }

    // MARK: - ⌥Tab switcher

    /// Like macOS's app switcher: icons in a row, the selected one in a
    /// rounded highlight, its window title underneath.
    func switcher(_ hud: HUDModel, _ theme: Theme, _ view: HUDView, key: Int) -> HUDLayer? {
        guard !hud.rows.isEmpty else { return nil }
        let look = theme.look
        let s = view.scale * look.hudScale
        let pad = 12 * s, tileGap = 4 * s, tile = 104 * s, icon = 80 * s
        let m = theme.shadowMargin(s)
        let maxTiles = max(1, Int((view.size.width * 0.9 - pad * 2 + tileGap) / (tile + tileGap)))
        let count = hud.rows.count
        let shown = min(count, maxTiles)
        let selected = min(max(hud.selectedRow ?? 0, 0), count - 1)
        let first = max(0, min(selected - shown / 2, count - shown))
        let titleStyle = TextStyle(size: look.titleSize * s)
        let titleBand = 44 * s // the title, then as much room below it as above the icons
        let width = CGFloat(shown) * tile + CGFloat(shown - 1) * tileGap + pad * 2
        let height = pad + tile + titleBand
        let radius = 22 * s, highlightRadius = radius - pad // concentric with the panel's corners

        guard let b = Bitmap(width: Int(ceil(width + m * 2)), height: Int(ceil(height + m * 2))) else { return nil }
        let box = CGRect(x: m, y: m, width: width, height: height)
        panel(b, box, radius, s, theme, opaque: true)

        for i in 0..<shown {
            let index = first + i
            let row = hud.rows[index]
            let r = CGRect(x: m + pad + CGFloat(i) * (tile + tileGap), y: m + pad, width: tile, height: tile)
            if index == selected { b.fill(b.roundedPath(r, highlightRadius), theme.highlight) }
            appIcon(b, CGRect(x: r.midX - icon / 2, y: r.midY - icon / 2, width: icon, height: icon), bundleID: row.bundleID,
                    fallback: row.detail.isEmpty ? row.title : row.detail, theme)
        }
        // More icons that way: a chevron centred in the side padding.
        if first > 0 { chevron(b, x: m + pad / 2, cy: m + pad + tile / 2, pointsLeft: true, s: s, theme.textFaint) }
        if first + shown < count { chevron(b, x: m + width - pad / 2, cy: m + pad + tile / 2, pointsLeft: false, s: s, theme.textFaint) }

        let row = hud.rows[selected]
        let line = type.fit(type.line(row.title.isEmpty ? row.detail : row.title, titleStyle, theme.text), width - 40 * s, titleStyle, theme.text)
        b.draw(line, x: (m + width / 2 - lineWidth(line) / 2).rounded(), cy: (m + pad + tile + 14 * s).rounded(),
               capHeight: type.capHeight(titleStyle))
        let origin = CGPoint(x: ((view.size.width - CGFloat(b.width)) / 2).rounded(),
                             y: ((view.size.height - CGFloat(b.height)) / 2).rounded())
        return layer(b, key: key, at: origin, panel: box, radius: radius)
    }

    /// A small chevron, 4 by 8 points with round ends, centred on `x`.
    private func chevron(_ b: Bitmap, x: CGFloat, cy: CGFloat, pointsLeft: Bool, s: CGFloat, _ color: CGColor) {
        let w = 4 * s * (pointsLeft ? -1 : 1), h = 4 * s
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x - w / 2, y: cy - h))
        path.addLine(to: CGPoint(x: x + w / 2, y: cy))
        path.addLine(to: CGPoint(x: x - w / 2, y: cy + h))
        b.ctx.saveGState()
        b.ctx.setLineCap(.round)
        b.ctx.setLineJoin(.round)
        b.stroke(path, color, width: 1.5 * s)
        b.ctx.restoreGState()
    }

    // MARK: - Pills: the status readout and the key hints

    /// `index`: 0 top-left, 1 top-right, 2 bottom center, 3 bottom-right.
    /// `{...}` spans are drawn as keycaps.
    func corner(_ textValue: String, index: Int, _ theme: Theme, _ view: HUDView, key: Int) -> HUDLayer? {
        guard !textValue.isEmpty else { return nil }
        let look = theme.look
        let s = view.scale * look.hudScale
        let style = TextStyle(size: look.cornerSize * s)
        let m = theme.shadowMargin(s)
        let height = (PaletteMetrics.hintsHeight(look) * view.scale).rounded(), padX = 12 * s
        let width = (hints(nil, textValue, style, x: 0, cy: 0, s: s, theme) + padX * 2).rounded(.up)
        guard let b = Bitmap(width: Int(width + m * 2), height: Int(height + m * 2)) else { return nil }
        let box = CGRect(x: m, y: m, width: width, height: height)
        panel(b, box, height / 2, s, theme)
        hints(b, textValue, style, x: m + padX, cy: m + height / 2, s: s, theme)

        let margin = 20 * s
        let top = max(margin, view.topInset + 10 * s)
        var bottom = view.size.height - PaletteMetrics.hintsMargin(look, bottomInset: view.bottomInset / view.scale) * view.scale - height
        if index == 3, let minimapTop = view.minimapTop { bottom = min(bottom, minimapTop - 12 * s - height) }
        let x: CGFloat = switch index {
        case 0: margin
        case 2: (view.size.width - width) / 2
        default: view.size.width - margin - width
        }
        let origin = CGPoint(x: (x - m).rounded(), y: ((index < 2 ? top : bottom) - m).rounded())
        return layer(b, key: key, at: origin, panel: box, radius: height / 2)
    }

    // MARK: - Toast

    /// A short notice in the same pill as the key hints, `{...}` as keycaps.
    func toast(_ message: String, _ theme: Theme, _ view: HUDView, key: Int) -> HUDLayer? {
        let s = view.scale * theme.look.hudScale
        let style = TextStyle(size: 13 * s)
        let m = theme.shadowMargin(s)
        let height = (32 * s).rounded(), padX = 16 * s
        let width = (hints(nil, message, style, x: 0, cy: 0, s: s, theme) + padX * 2).rounded(.up)
        guard let b = Bitmap(width: Int(width + m * 2), height: Int(height + m * 2)) else { return nil }
        let box = CGRect(x: m, y: m, width: width, height: height)
        panel(b, box, height / 2, s, theme, opaque: true)
        hints(b, message, style, x: m + padX, cy: box.midY, s: s, theme, color: theme.text)
        let y = view.size.height * 0.78 - height / 2 - m
        return layer(b, key: key, at: CGPoint(x: ((view.size.width - CGFloat(b.width)) / 2).rounded(), y: y.rounded()),
                     panel: box, radius: height / 2)
    }

    // MARK: - Labels drawn in the world, under the lens

    /// A window's name, as Mission Control shows it under the window: app
    /// icon and title in a pill, at most 460 points wide.
    func label(title: String, bundleID: String?, scale s: CGFloat, _ theme: Theme) -> MTLTexture? {
        let look = theme.look, u = look.labelSize / 12
        let style = TextStyle(size: look.labelSize * s, weight: .medium)
        let height = (26 * u * s).rounded(), icon = (16 * u * s).rounded()
        let image = icons.icon(bundleID: bundleID, px: Int(icon)) // no icon: just the title
        let textX = image == nil ? 12 * s : 6 * u * s + icon + 6 * s, padRight = 12 * s
        let width = min(measure(title, style) + textX + padRight, 460 * s).rounded(.up)
        guard let b = Bitmap(width: Int(width), height: Int(height)) else { return nil }
        let path = b.roundedPath(CGRect(x: 0.5, y: 0.5, width: width - 1, height: height - 1), height / 2)
        b.fill(path, theme.panel.withAlphaComponent(look.reduceTransparency ? 1 : 0.94))
        if look.liquid { glassLight(b, CGRect(x: 0, y: 0, width: width, height: height), height / 2, s, theme) }
        b.stroke(path, theme.edge, width: 1)
        if let image { b.draw(image, in: CGRect(x: 6 * u * s, y: ((height - icon) / 2).rounded(), width: icon, height: icon)) }
        text(b, title, style, theme.text, x: textX, cy: height / 2, maxWidth: width - textX - padRight)
        return b.texture(device: device)
    }

    /// A workspace's tag: its number in semibold 13 and its mode in 11, in a
    /// pill; the current workspace's pill in the accent color.
    func workspaceLabel(number: Int?, mode: LayoutMode, current: Bool, scale s: CGFloat, _ theme: Theme) -> MTLTexture? {
        let numberStyle = TextStyle(size: 13 * s, weight: .semibold), modeStyle = TextStyle(size: 11 * s)
        let modeName = mode.rawValue.prefix(1).uppercased() + mode.rawValue.dropFirst()
        let numberText = number.map(String.init) ?? ""
        let gap = numberText.isEmpty ? 0 : 6 * s
        let height = (26 * s).rounded()
        let width = ceil(measure(numberText, numberStyle) + gap + measure(modeName, modeStyle) + 22 * s)
        guard let b = Bitmap(width: Int(width), height: Int(height)) else { return nil }
        let path = b.roundedPath(CGRect(x: 0.5, y: 0.5, width: width - 1, height: height - 1), height / 2)
        b.fill(path, current ? theme.accent : theme.panel.withAlphaComponent(theme.look.reduceTransparency ? 1 : 0.85))
        if theme.look.liquid { glassLight(b, CGRect(x: 0, y: 0, width: width, height: height), height / 2, s, theme) }
        if !current { b.stroke(path, theme.edge, width: 1) }
        let x = 11 * s + text(b, numberText, numberStyle, current ? theme.onAccent : theme.text, x: 11 * s, cy: height / 2) + gap
        text(b, modeName, modeStyle, current ? theme.onAccent.withAlphaComponent(0.85) : theme.textDim, x: x, cy: height / 2)
        return b.texture(device: device)
    }

    /// A notice drawn in the world's place (an empty workspace's message): the hint pill, `{...}` as keycaps.
    func notice(_ message: String, scale s: CGFloat, _ theme: Theme) -> MTLTexture? {
        let style = TextStyle(size: 13 * s)
        let height = (32 * s).rounded(), padX = 16 * s
        let width = (hints(nil, message, style, x: 0, cy: 0, s: s, theme) + padX * 2).rounded(.up)
        guard let b = Bitmap(width: Int(width), height: Int(height)) else { return nil }
        let path = b.roundedPath(CGRect(x: 0.5, y: 0.5, width: width - 1, height: height - 1), height / 2)
        b.fill(path, theme.panel.withAlphaComponent(theme.look.reduceTransparency ? 1 : 0.94))
        if theme.look.liquid { glassLight(b, CGRect(x: 0, y: 0, width: width, height: height), height / 2, s, theme) }
        b.stroke(path, theme.edge, width: 1)
        hints(b, message, style, x: padX, cy: height / 2, s: s, theme, color: theme.text)
        return b.texture(device: device)
    }
}
