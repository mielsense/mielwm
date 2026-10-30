import AppKit
import MielCore
import SwiftUI

// The overview's chrome in SwiftUI: the search capsule with its card of
// results or shortcuts, the key hints, the ⌥Tab switcher and toasts. Sizes
// follow the app's design values times the HUD scale: 13 point rows, 11
// point secondary text, semibold titles, spacing in steps of 4, continuous
// corners, and inner radii that are the outer radius minus the padding.

/// The palette and the pills: they fade in as the camera zooms out.
struct EasedChrome: View {
    @ObservedObject var model: ChromeModel

    var body: some View {
        let c = model.content, s = c.look.hudScale
        ZStack(alignment: .top) {
            if c.hud.mode == .search || c.hud.mode == .help {
                Palette(content: c)
                    .padding(.top, PaletteMetrics.top(c.look, screenHeight: c.size.height, topInset: c.topInset))
            }
            if let hints = c.hud.corners[safe: 2], !hints.isEmpty {
                Pill(text: hints, look: c.look, worldShown: c.worldShown)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, PaletteMetrics.hintsMargin(c.look, bottomInset: c.bottomInset))
            }
            if let readout = c.hud.corners[safe: 1], !readout.isEmpty {
                Pill(text: readout, look: c.look, worldShown: c.worldShown)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, max(20 * s, c.topInset + 10 * s))
                    .padding(.trailing, 20 * s)
            }
        }
        .frame(width: c.size.width, height: c.size.height, alignment: .top)
        .environment(\.colorScheme, c.look.dark ? .dark : .light)
    }
}

/// The ⌥Tab switcher and toasts: they show at once.
struct SteadyChrome: View {
    @ObservedObject var model: ChromeModel

    var body: some View {
        let c = model.content
        ZStack {
            if c.hud.mode == .switcher, !c.hud.rows.isEmpty {
                Switcher(content: c)
                    .position(x: c.size.width / 2, y: c.size.height / 2)
            }
            if let toast = c.hud.toast, !toast.isEmpty {
                Pill(text: toast, look: c.look, worldShown: c.worldShown, toast: true)
                    .opacity(c.toastOpacity)
                    .position(x: c.size.width / 2, y: c.size.height * 0.78) // where the notices put theirs
            }
        }
        .frame(width: c.size.width, height: c.size.height)
        .environment(\.colorScheme, c.look.dark ? .dark : .light)
    }
}

// MARK: - Palette

private struct Palette: View {
    let content: ChromeContent

    var body: some View {
        let hud = content.hud, look = content.look, s = look.hudScale
        let help = hud.mode == .help
        let list = hud.mode == .search && (!hud.rows.isEmpty || !hud.query.isEmpty)
        let width = min((help ? max(look.paletteWidth, PaletteMetrics.helpWidth) : look.paletteWidth) * s, content.size.width * 0.94)
        VStack(spacing: PaletteMetrics.cardGap * s) {
            SearchField(hud: hud, look: look)
                .frame(width: width, height: look.searchHeight * s)
                .chromeMaterial(Capsule(), look: look)
            if list || help {
                Group {
                    if help { HelpSheet(sections: hud.help, look: look) } else { Results(hud: hud, look: look) }
                }
                .frame(width: width)
                .chromeMaterial(RoundedRectangle(cornerRadius: PaletteMetrics.cardRadius * s, style: .continuous), look: look)
            }
        }
    }
}

/// Spotlight's field: a magnifying glass, then the query in the biggest size.
private struct SearchField: View {
    let hud: HUDModel
    let look: Look

    var body: some View {
        let s = look.hudScale, size = look.querySize * s
        HStack(spacing: 12 * s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: (size * 0.8).rounded(), weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 1 * s) {
                if hud.query.isEmpty, hud.markedText.isEmpty {
                    Caret(height: (size * 1.15).rounded(), color: look.accent, moves: "")
                    Text(hud.placeholder).foregroundStyle(.tertiary).padding(.leading, 3 * s)
                } else {
                    (Text(hud.query) + Text(hud.markedText).underline())
                        .lineLimit(1)
                        .truncationMode(.head) // the end of a long query stays in view, by the caret
                    Caret(height: (size * 1.15).rounded(), color: look.accent, moves: hud.query + hud.markedText)
                }
            }
            .font(.system(size: size))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20 * s)
    }
}

private struct Results: View {
    let hud: HUDModel
    let look: Look

    var body: some View {
        let s = look.hudScale, inset = PaletteMetrics.listInset * s, rowHeight = look.rowHeight * s
        let count = min(hud.rows.count, max(1, look.paletteRows))
        VStack(spacing: 0) {
            if hud.rows.isEmpty {
                Text("No windows match \"\(hud.query)\"")
                    .font(.system(size: look.titleSize * s))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                    .padding(.horizontal, 12 * s)
            }
            ForEach(0 ..< count, id: \.self) { i in
                ResultRow(row: hud.rows[i], selected: i == hud.selectedRow, look: look)
                    .frame(height: rowHeight)
            }
            if !hud.footer.isEmpty {
                Text(hud.footer)
                    .font(.system(size: look.detailSize * s))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: PaletteMetrics.footerHeight * s, alignment: .leading)
                    .padding(.horizontal, 12 * s)
            }
        }
        .padding(inset)
    }
}

private struct ResultRow: View {
    let row: HUDRow
    let selected: Bool
    let look: Look

    var body: some View {
        let s = look.hudScale, icon = (look.rowHeight * 0.66).rounded() * s
        let onAccent = Color(nsColor: look.accent.onAccent)
        HStack(spacing: 10 * s) {
            AppIcon(bundleID: row.bundleID).frame(width: icon, height: icon)
            VStack(alignment: .leading, spacing: 1 * s) {
                Text(highlighted(row.title, row.highlights))
                    .font(.system(size: look.titleSize * s))
                    .foregroundStyle(selected ? onAccent : .primary)
                if !row.detail.isEmpty {
                    Text(row.detail)
                        .font(.system(size: look.detailSize * s))
                        .foregroundStyle(selected ? onAccent.opacity(0.8) : .secondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 8 * s)
            if !row.trailing.isEmpty {
                KeyCap(row.trailing, size: look.detailSize * s, onAccent: selected ? onAccent : nil)
            }
        }
        .padding(.leading, 8 * s)
        .padding(.trailing, 10 * s)
        .frame(maxHeight: .infinity)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: (PaletteMetrics.cardRadius - PaletteMetrics.listInset) * s, style: .continuous)
                    .fill(Color(look.accent))
            }
        }
    }

    /// The title with the letters the search matched in semibold.
    private func highlighted(_ title: String, _ ranges: [Range<Int>]) -> AttributedString {
        var out = AttributedString(title)
        let chars = Array(out.characters.indices)
        for r in ranges where r.lowerBound >= 0 && r.upperBound <= chars.count && !r.isEmpty {
            let end = r.upperBound < chars.count ? chars[r.upperBound] : out.endIndex
            out[chars[r.lowerBound] ..< end].font = .system(size: look.titleSize * look.hudScale, weight: .semibold)
        }
        return out
    }
}

/// macOS's keyboard-shortcuts sheet: a title, then three columns of sections.
private struct HelpSheet: View {
    let sections: [HelpSection]
    let look: Look

    var body: some View {
        let s = look.hudScale
        VStack(alignment: .leading, spacing: 0) {
            Text("Shortcuts")
                .font(.system(size: 17 * s, weight: .semibold))
                .frame(height: HelpSection.titleBand * s)
            HStack(alignment: .top, spacing: 24 * s) {
                ForEach(Array(HelpSection.columns(sections, count: 3).enumerated()), id: \.offset) { _, column in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(column, id: \.title) { section in
                            Text(section.title)
                                .font(.system(size: 13 * s, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(height: HelpSection.headerHeight * s)
                            ForEach(Array(section.entries.enumerated()), id: \.offset) { _, entry in
                                HStack(spacing: 8 * s) {
                                    Text(entry.action).font(.system(size: 13 * s)).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Keys(keys: entry.keys, size: 11 * s)
                                }
                                .frame(height: HelpSection.lineHeight * s)
                            }
                            Spacer().frame(height: HelpSection.gap * s)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 24 * s)
        .padding(.bottom, 8 * s)
    }
}

/// A help entry's keys: capsules for keys, plain words (Click, drag) as text.
private struct Keys: View {
    let keys: String
    let size: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(HelpSection.keyTokens(keys).enumerated()), id: \.offset) { _, token in
                if token.isKey { KeyCap(token.text, size: size) } else { Text(token.text).font(.system(size: size)).foregroundStyle(.secondary) }
            }
        }
        .fixedSize()
    }
}

// MARK: - Pills

/// The key hints, the readout and toasts: text with `{...}` as keycaps, in a capsule.
private struct Pill: View {
    let text: String
    let look: Look
    let worldShown: Bool
    var toast = false

    var body: some View {
        let s = look.hudScale
        let size = toast ? 13 * s : look.cornerSize * s
        let segments = hintSegments(text).map { (text: $0.text.trimmingCharacters(in: .whitespaces), isKey: $0.isKey) }.filter { !$0.text.isEmpty }
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { i, segment in
                if i > 0 {
                    let before = segments[i - 1].isKey
                    Spacer().frame(width: (before && !segment.isKey ? 6 : before && segment.isKey ? 4 : 16) * s)
                }
                if segment.isKey {
                    KeyCap(segment.text, size: (toast ? 11 : look.cornerSize - 1) * s)
                } else {
                    Text(segment.text).font(.system(size: size)).foregroundStyle(toast ? .primary : .secondary)
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, (toast ? 16 : 12) * s)
        .frame(height: toast ? 36 * s : PaletteMetrics.hintsHeight(look))
        .chromeMaterial(Capsule(), look: look, behindWindow: !worldShown)
    }
}

// MARK: - ⌥Tab switcher

/// Like macOS's app switcher: icons in a row, the selected one raised, its window's title below.
private struct Switcher: View {
    let content: ChromeContent

    var body: some View {
        let hud = content.hud, look = content.look, s = look.hudScale
        let pad = 12 * s, gap = 4 * s, tile = 104 * s, icon = 80 * s, radius = 22 * s
        let count = hud.rows.count
        let (first, shown, selected) = PaletteMetrics.switcherWindow(count: count, selected: hud.selectedRow,
                                                                     maxTiles: Int((content.size.width * 0.9 - pad * 2 + gap) / (tile + gap)))
        let row = hud.rows[selected]
        VStack(spacing: 0) {
            HStack(spacing: gap) {
                ForEach(first ..< first + shown, id: \.self) { i in
                    AppIcon(bundleID: hud.rows[i].bundleID)
                        .frame(width: icon, height: icon)
                        .frame(width: tile, height: tile)
                        .background {
                            if i == selected {
                                RoundedRectangle(cornerRadius: radius - pad, style: .continuous).fill(.primary.opacity(0.12))
                            }
                        }
                }
            }
            Text(row.title.isEmpty ? row.detail : row.title)
                .font(.system(size: look.titleSize * s))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: CGFloat(shown) * (tile + gap) - 40 * s)
                .frame(height: 40 * s)
        }
        .padding([.top, .horizontal], pad)
        .overlay(alignment: .leading) { if first > 0 { Chevron(left: true, pad: pad, tile: tile) } }
        .overlay(alignment: .trailing) { if first + shown < count { Chevron(left: false, pad: pad, tile: tile) } }
        .chromeMaterial(RoundedRectangle(cornerRadius: radius, style: .continuous), look: look, behindWindow: !content.worldShown)
    }
}

/// More icons that way: a chevron in the side padding, level with the icons.
private struct Chevron: View {
    let left: Bool
    let pad: CGFloat
    let tile: CGFloat

    var body: some View {
        Image(systemName: left ? "chevron.left" : "chevron.right")
            .font(.system(size: pad * 0.8, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: pad)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, pad + tile / 2 - pad / 2)
    }
}

// MARK: - Shared pieces

/// A key as a light capsule behind its glyphs.
struct KeyCap: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let key: String
    let size: CGFloat
    var onAccent: Color?

    init(_ key: String, size: CGFloat, onAccent: Color? = nil) {
        self.key = key
        self.size = size
        self.onAccent = onAccent
    }

    var body: some View {
        let height = (size * 1.6).rounded()
        Text(key)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(onAccent.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
            .padding(.horizontal, size * 0.42)
            .frame(minWidth: height, minHeight: height)
            .background(Capsule().fill(onAccent != nil ? AnyShapeStyle(.white.opacity(0.22)) : AnyShapeStyle(.primary.opacity(contrast == .increased ? 0.2 : 0.1))))
            .fixedSize()
    }
}

private struct AppIcon: View {
    let bundleID: String?

    var body: some View {
        Image(nsImage: AppInfo.icon(for: bundleID))
            .resizable()
            .interpolation(.high)
    }
}

/// The search field's caret, blinked by Core Animation like the system's, so an
/// idle field costs no frames; it starts again, solid, whenever the text changes.
private struct Caret: NSViewRepresentable {
    let height: CGFloat
    let color: RGB
    let moves: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        view.layer?.backgroundColor = NSColor(color).cgColor
        guard view.layer?.animation(forKey: "blink") == nil || context.coordinator.moves != moves else { return }
        context.coordinator.moves = moves
        view.layer?.add(Self.blink, forKey: "blink")
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        CGSize(width: 2, height: height)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { var moves = "" }

    /// On, a quick fade out, off, a fade back in, as the overlay's caret did.
    private static let blink: CAKeyframeAnimation = {
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = [1, 1, 0, 0, 1]
        a.keyTimes = [0, 0.42, 0.5, 0.92, 1]
        let linear = CAMediaTimingFunction(name: .linear), ease = CAMediaTimingFunction(name: .easeInEaseOut)
        a.timingFunctions = [linear, ease, linear, ease]
        a.duration = 1.06
        a.repeatCount = .infinity
        return a
    }()
}

// MARK: - Material

extension View {
    /// Liquid glass, frosted, or solid with Reduce Transparency; outlined with Increase Contrast.
    /// `behindWindow`: what to blur is the desktop behind the overlay, not the canvas inside it (frosted only).
    func chromeMaterial<S: InsettableShape>(_ shape: S, look: Look, behindWindow: Bool = false) -> some View {
        modifier(ChromeMaterial(shape: shape, look: look, behindWindow: behindWindow))
    }
}

private struct ChromeMaterial<S: InsettableShape>: ViewModifier {
    let shape: S
    let look: Look
    let behindWindow: Bool

    func body(content: Content) -> some View {
        Group {
            switch NoticeMaterial.current(look) {
            case .solid:
                content.background(shape.fill(Color(nsColor: .windowBackgroundColor)))
                    .shadow(color: .black.opacity(look.dark ? 0.4 : 0.2), radius: 14, y: 4)
            case .glass:
                if #available(macOS 26, *) { content.glassEffect(.regular, in: shape) }
            case .hud:
                content.background(Frosted(behindWindow: behindWindow).clipShape(shape))
                    .shadow(color: .black.opacity(look.dark ? 0.4 : 0.2), radius: 14, y: 4)
            }
        }
        .overlay { if look.increaseContrast { shape.strokeBorder(.primary.opacity(0.6), lineWidth: 1) } }
    }
}

/// The frosted HUD material of macOS before 26.
private struct Frosted: NSViewRepresentable {
    let behindWindow: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.blendingMode = behindWindow ? .behindWindow : .withinWindow
    }
}

extension Color {
    init(_ c: RGB) { self.init(.sRGB, red: c.r, green: c.g, blue: c.b) }
}

extension NSColor {
    convenience init(_ c: RGB) { self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1) }
}

extension RGB {
    /// Text on the accent: dark on a light one, white on the rest.
    var onAccent: NSColor { wantsDarkText ? NSColor(white: 0, alpha: 0.85) : .white }
}

extension AppInfo {
    /// The app's icon, or the generic one without a bundle id.
    @MainActor static func icon(for bundleID: String?) -> NSImage {
        bundleID.map { AppInfo(bundleID: $0).icon } ?? NSWorkspace.shared.icon(for: .applicationBundle)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
