import AppKit
import MielCore

// What the notice panels draw: the toast, the workspace pill and the stack
// strip. Each is a capsule; whatever sits inside one is a capsule too, its
// radius the outer radius minus the padding, so the curves share a centre.
// Text is 13 points, secondary text 11; spacing steps by 4.

enum NoticeContent: Equatable {
    case toast(String)
    case workspace(WorkspaceNotice)
    case stack(StackNotice)
}

/// A notice's size, its corner radius, and its content drawn into a flipped view.
struct NoticeDrawing {
    var size: NSSize
    var radius: CGFloat
    var draw: @MainActor (NSRect) -> Void
}

@MainActor
func noticeDrawing(_ content: NoticeContent, accent: RGB, material: Design.ChromeMaterial, increaseContrast: Bool,
                   maxWidth: CGFloat) -> NoticeDrawing {
    let ink = NoticeInk(accent: accent, material: material, increaseContrast: increaseContrast)
    switch content {
    case let .toast(text): return toastDrawing(text, ink)
    case let .workspace(n): return workspaceDrawing(n, ink)
    case let .stack(n): return stackDrawing(n, ink, maxWidth: maxWidth)
    }
}

/// Colours, resolved when drawn so they follow the panel's appearance.
private struct NoticeInk {
    var accent: RGB
    var material: Design.ChromeMaterial
    var increaseContrast: Bool

    var primary: NSColor { .labelColor }
    var secondary: NSColor { increaseContrast ? .labelColor : .secondaryLabelColor }
    var accentFill: NSColor { NSColor(accent) }
    var onAccent: NSColor { accent.onAccent }
    /// The front window's capsule in the stack strip.
    var raised: NSColor { NSColor.labelColor.withAlphaComponent(increaseContrast ? 0.2 : 0.1) }
    /// A key cap's fill and text, after `Design.KeyCap`.
    var keyFill: NSColor { NSColor.labelColor.withAlphaComponent(Design.KeyCap.fill(on: material)) }
    var keyText: NSColor { NSColor.labelColor.withAlphaComponent(Design.KeyCap.text) }
}

// MARK: Text

/// One line of text, set so its cap height centres on `midY`, as the eye reads it.
@MainActor
private func drawLine(_ text: String, font: NSFont, color: NSColor, x: CGFloat, midY: CGFloat, maxWidth: CGFloat = .greatestFiniteMagnitude,
                      tracking: CGFloat = 0) {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byTruncatingTail
    let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style, .kern: tracking])
    let baseline = (midY + font.capHeight / 2).rounded()
    let width = min(ceil(string.size().width), maxWidth)
    string.draw(with: NSRect(x: x, y: baseline - font.ascender, width: width, height: ceil(font.ascender - font.descender)),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
}

private func width(_ text: String, _ font: NSFont, tracking: CGFloat = 0) -> CGFloat {
    ceil(NSAttributedString(string: text, attributes: [.font: font, .kern: tracking]).size().width)
}

// MARK: Toast

/// "Tidied 4 windows  {⌘Z} Undo": text, with `{...}` as keycaps.
@MainActor
private func toastDrawing(_ text: String, _ ink: NoticeInk) -> NoticeDrawing {
    let font = NSFont.systemFont(ofSize: Design.rowSize), keyFont = NSFont.systemFont(ofSize: Design.secondarySize)
    // Key caps after `Design.KeyCap`, at the secondary size.
    let k = Design.secondarySize / Design.rowSize
    let height = Design.Pill.height, padX = Design.Space.m + Design.Space.xs
    let keyHeight = (Design.KeyCap.minHeight * k).rounded(), keyPad = Design.KeyCap.padding.leading * k, tracking = Design.KeyCap.tracking * k
    let runs = hintSegments(text).map { (text: $0.text, key: $0.isKey) }
    let runWidth = { (r: (text: String, key: Bool)) in
        r.key ? max(width(r.text, keyFont, tracking: tracking) + keyPad * 2, keyHeight) : width(r.text, font)
    }
    let total = runs.map(runWidth).reduce(0, +)
    return NoticeDrawing(size: NSSize(width: ceil(total + padX * 2), height: height), radius: height / 2) { bounds in
        var x = bounds.minX + padX
        for r in runs {
            let w = runWidth(r)
            if r.key {
                let box = NSRect(x: x, y: bounds.midY - keyHeight / 2, width: w, height: keyHeight)
                let cap = NSBezierPath(roundedRect: box, xRadius: Design.KeyCap.radius * k, yRadius: Design.KeyCap.radius * k)
                ink.keyFill.setFill()
                cap.fill()
                if ink.increaseContrast {
                    NSColor.separatorColor.setStroke()
                    cap.stroke()
                }
                drawLine(r.text, font: keyFont, color: ink.keyText, x: box.minX + (w - width(r.text, keyFont, tracking: tracking)) / 2,
                         midY: bounds.midY, tracking: tracking)
            } else {
                drawLine(r.text, font: font, color: ink.primary, x: x, midY: bounds.midY)
            }
            x += w
        }
    }
}

// MARK: Workspace pill

/// The numbers of the workspaces with windows, the current one on an accent circle.
@MainActor
private func workspaceDrawing(_ n: WorkspaceNotice, _ ink: NoticeInk) -> NoticeDrawing {
    let slot: CGFloat = 28, pad = Design.Space.s, gap = Design.Space.xs
    let height = slot + pad * 2, radius = height / 2 // 22: the current number's circle, 14, is concentric
    let font = NSFont.monospacedDigitSystemFont(ofSize: Design.rowSize, weight: .semibold)
    let count = CGFloat(n.numbers.count)
    let size = NSSize(width: pad * 2 + count * slot + (count - 1) * gap, height: height)
    return NoticeDrawing(size: size, radius: radius) { bounds in
        for (i, number) in n.numbers.enumerated() {
            let r = NSRect(x: bounds.minX + pad + CGFloat(i) * (slot + gap), y: bounds.minY + pad, width: slot, height: slot)
            let current = number == n.current
            if current {
                ink.accentFill.setFill()
                NSBezierPath(ovalIn: r).fill()
            }
            let text = String(number)
            drawLine(text, font: font, color: current ? ink.onAccent : ink.secondary, x: r.midX - width(text, font) / 2, midY: r.midY)
        }
    }
}

// MARK: Stack strip

/// The stacked windows in their order, icon and short title, the front one
/// raised, then "2 of 4". Titles go when they don't fit: the others' first, then the front one's.
@MainActor
private func stackDrawing(_ n: StackNotice, _ ink: NoticeInk, maxWidth: CGFloat) -> NoticeDrawing {
    let chip = Design.Pill.height, pad = Design.Space.xs, gap = Design.Space.xs, icon: CGFloat = 20, maxTitle: CGFloat = 160
    let height = chip + pad * 2, radius = height / 2 // 22; chips are 18, concentric
    let titleFont = NSFont.systemFont(ofSize: Design.rowSize), frontFont = NSFont.systemFont(ofSize: Design.rowSize, weight: .medium)
    let countFont = NSFont.monospacedDigitSystemFont(ofSize: Design.secondarySize, weight: .regular)
    let iconInset = (chip - icon) / 2 // 8, so the icon sits as far from the chip's edge on every side
    let position = n.position, countWidth = width(position, countFont)
    let titleWidths = n.entries.enumerated().map { i, e in min(width(e.title, i == n.front ? frontFont : titleFont), maxTitle) }

    func chipWidth(_ i: Int, titles: Int) -> CGFloat { // titles: 2 every chip, 1 the front one, 0 none
        let titled = titles == 2 || (titles == 1 && i == n.front)
        return titled ? iconInset + icon + Design.Space.s + titleWidths[i] + Design.Space.m : chip
    }
    func total(_ titles: Int) -> CGFloat {
        pad * 2 + n.entries.indices.map { chipWidth($0, titles: titles) }.reduce(0, +) + CGFloat(n.entries.count - 1) * gap + Design.Space.m + countWidth + Design.Space.m
    }
    let titles = [2, 1, 0].first { total($0) <= maxWidth } ?? 0
    return NoticeDrawing(size: NSSize(width: total(titles), height: height), radius: radius) { bounds in
        var x = bounds.minX + pad
        for (i, e) in n.entries.enumerated() {
            let w = chipWidth(i, titles: titles), r = NSRect(x: x, y: bounds.minY + pad, width: w, height: chip)
            let front = i == n.front
            if front {
                ink.raised.setFill()
                NSBezierPath(roundedRect: r, xRadius: chip / 2, yRadius: chip / 2).fill()
            }
            let image = AppInfo.icon(for: e.bundleID)
            image.draw(in: NSRect(x: r.minX + iconInset, y: r.minY + iconInset, width: icon, height: icon), from: .zero, operation: .sourceOver,
                       fraction: front ? 1 : 0.7, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
            if w > chip {
                drawLine(e.title, font: front ? frontFont : titleFont, color: front ? ink.primary : ink.secondary,
                         x: r.minX + iconInset + icon + Design.Space.s, midY: r.midY, maxWidth: titleWidths[i])
            }
            x += w + gap
        }
        drawLine(position, font: countFont, color: ink.secondary, x: x - gap + Design.Space.m, midY: bounds.midY)
    }
}
