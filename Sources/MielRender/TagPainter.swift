import AppKit
import CoreText
import Metal
import MielCore

// Window names, workspace pills and empty workspaces' messages, rasterized
// with Core Text into textures that are composited after the lens, so text
// is never bent. Every length is in device pixels (`s` = backing scale).

final class TagPainter {
    let device: MTLDevice
    let type = Typesetter()
    let icons = IconCache()

    init(device: MTLDevice) {
        self.device = device
    }

    /// Draws `string` vertically centered on `cy`, ellipsized to `maxWidth`. Returns its width.
    @discardableResult
    private func text(_ b: Bitmap, _ string: String, _ style: TextStyle, _ color: CGColor, x: CGFloat, cy: CGFloat,
                      maxWidth: CGFloat = 0) -> CGFloat {
        var line = type.line(string, style, color)
        if maxWidth > 0 { line = type.fit(line, maxWidth, style, color) }
        return b.draw(line, x: x, cy: cy, capHeight: type.capHeight(style))
    }

    private func measure(_ string: String, _ style: TextStyle) -> CGFloat {
        lineWidth(type.line(string, style, rgba(1, 1, 1)))
    }

    // MARK: - Keycaps

    /// Key caps after `KeyCapMetrics`, the recipe Settings and the HUD draw: `size` is the text's.
    private func keycapStyle(_ size: CGFloat) -> TextStyle {
        TextStyle(size: size, tracking: KeyCapMetrics.tracking * size / KeyCapMetrics.textSize)
    }

    private func keycapHeight(_ style: TextStyle) -> CGFloat { (KeyCapMetrics.minHeight * style.size / KeyCapMetrics.textSize).rounded() }

    private func keycapWidth(_ key: String, _ style: TextStyle) -> CGFloat {
        max(measure(key, style) + 2 * KeyCapMetrics.paddingAcross * style.size / KeyCapMetrics.textSize, keycapHeight(style))
    }

    /// One key on the panel's solid fill. Returns its width.
    @discardableResult
    private func keycap(_ b: Bitmap, _ key: String, _ style: TextStyle, x: CGFloat, cy: CGFloat, _ theme: Theme) -> CGFloat {
        let w = keycapWidth(key, style), h = keycapHeight(style), k = style.size / KeyCapMetrics.textSize
        let box = CGRect(x: x, y: (cy - h / 2).rounded(), width: w, height: h)
        let primary: CGFloat = theme.look.dark ? 1 : 0
        b.fill(b.roundedPath(box, KeyCapMetrics.radius * k), rgba(primary, primary, primary, KeyCapMetrics.rest))
        text(b, key, style, rgba(primary, primary, primary, KeyCapMetrics.textOpacity), x: box.midX - measure(key, style) / 2, cy: cy)
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
                cx += b.map { keycap($0, piece, caps, x: cx, cy: cy, theme) } ?? keycapWidth(piece, caps)
            } else {
                if let b { text(b, piece, style, color ?? theme.textDim, x: cx, cy: cy) }
                cx += measure(piece, style)
            }
            previousKey = segment.isKey
        }
        return cx - x
    }

    // MARK: - Tags

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
        b.stroke(path, theme.edge, width: 1)
        hints(b, message, style, x: padX, cy: height / 2, s: s, theme, color: theme.text)
        return b.texture(device: device)
    }
}
