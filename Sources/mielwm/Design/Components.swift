import AppKit
import SwiftUI

/// A white glyph on a colored tile, as System Settings draws its icons: a soft
/// top-to-bottom shade, a faint highlight along the inner edge, and at header
/// size a soft shadow. An image (an app icon) is drawn as it is.
struct IconTile: View {
    enum Content { case symbol(String), image(NSImage) }

    let content: Content
    var tint: Color = Design.Tint.gray
    var size: CGFloat = Design.Tile.row

    init(_ symbol: String, tint: Color, size: CGFloat = Design.Tile.row) {
        content = .symbol(symbol)
        self.tint = tint
        self.size = size
    }

    init(image: NSImage, size: CGFloat = Design.Tile.row) {
        content = .image(image)
        self.size = size
    }

    var body: some View {
        Group {
            switch content {
            case let .image(image):
                Image(nsImage: image).resizable().interpolation(.high)
            case let .symbol(name):
                let tile = RoundedRectangle(cornerRadius: Design.Radius.tile(size), style: .continuous)
                ZStack {
                    tile.fill(LinearGradient(colors: [tint.mix(with: .white, by: 0.2), tint.mix(with: .black, by: 0.06)], startPoint: .top, endPoint: .bottom))
                    tile.strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: size >= 48 ? 1 : 0.5)
                    Image(systemName: name)
                        .resizable()
                        .scaledToFit()
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.15), radius: size / 40, y: size / 40)
                        .frame(width: size * Design.Tile.glyph, height: size * Design.Tile.glyph)
                }
                .shadow(color: .black.opacity(size >= 48 ? 0.18 : 0), radius: size / 16, y: size / 32)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The top of a pane: a filled card with its 48 pt icon, its name and one line
/// on what is in it, and optionally a control under that, like a search field.
struct PaneHeader<Accessory: View>: View {
    let pane: SettingsPane
    @ViewBuilder var accessory: Accessory

    init(pane: SettingsPane, @ViewBuilder accessory: () -> Accessory) {
        self.pane = pane
        self.accessory = accessory()
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                pane.icon(size: Design.Tile.header)
                Text(pane.title).font(Design.headerTitle).padding(.top, Design.Space.s)
                Text(pane.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 400)
                    .padding(.top, 2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            accessory.padding(.top, Accessory.self == EmptyView.self ? 0 : Design.Space.m)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Design.Space.m)
        .padding(.bottom, Design.Space.m + 2)
    }
}

extension PaneHeader where Accessory == EmptyView {
    init(pane: SettingsPane) { self.init(pane: pane) { EmptyView() } }
}

/// A row: an optional 24 pt icon, a title, an optional line under it, and controls at the end.
struct SettingsRow<Trailing: View>: View {
    var icon: IconTile?
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, subtitle: String? = nil, icon: IconTile? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.trailing = trailing()
    }

    var body: some View {
        LabeledContent {
            trailing
        } label: {
            HStack(spacing: Design.Space.s + 2) {
                if let icon { icon }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Design.row)
                    if let subtitle {
                        Text(subtitle).font(Design.secondary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// A choice you can see: a thumbnail per option with its name under it; the
/// chosen one has an accent ring and a bold name, as in System Settings > Appearance.
struct VisualPicker<Value: Hashable, Thumbnail: View>: View {
    let title: String
    var subtitle: String?
    @Binding var selection: Value
    let options: [Value]
    let name: (Value) -> String
    var size = CGSize(width: 64, height: 42)
    @ViewBuilder let thumbnail: (Value) -> Thumbnail

    var body: some View {
        LabeledContent {
            HStack(alignment: .top, spacing: Design.Space.m) {
                ForEach(options, id: \.self) { option in
                    let chosen = option == selection
                    Button { selection = option } label: {
                        VStack(spacing: 5) {
                            thumbnail(option)
                                .frame(width: size.width, height: size.height)
                                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.thumbnail, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Design.Radius.thumbnail, style: .continuous).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
                                .padding(3)
                                .overlay(RoundedRectangle(cornerRadius: Design.Radius.thumbnail + 3, style: .continuous)
                                    .strokeBorder(chosen ? Color.accentColor : .clear, lineWidth: 2.5))
                            Text(name(option))
                                .font(Design.secondary.weight(chosen ? .semibold : .regular))
                                .foregroundStyle(chosen ? .primary : .secondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name(option))
                    .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
        } label: {
            Text(title)
            if let subtitle { Text(subtitle) }
        }
    }
}

/// Keys in a light capsule, after the recipe in `Design.KeyCap`, at `size`
/// points of text. The fill follows the surface: the overview's panels set
/// `keyCapFill` for glass, and `onAccent` puts the cap on a selected row.
struct KeyCaps: View {
    let text: String
    var size = Design.KeyCap.textSize
    var onAccent: Color?
    var dim = false
    var hovering = false
    var recording = false
    @Environment(\.keyCapFill) private var fill
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let k = size / Design.KeyCap.textSize, p = Design.KeyCap.padding
        let cap = RoundedRectangle(cornerRadius: Design.KeyCap.radius * k, style: .continuous)
        Text(text)
            .font(.system(size: size))
            .tracking(Design.KeyCap.tracking * k)
            .foregroundStyle(textStyle)
            .lineLimit(1)
            .padding(EdgeInsets(top: p.top * k, leading: p.leading * k, bottom: p.bottom * k, trailing: p.trailing * k))
            .frame(minHeight: Design.KeyCap.minHeight * k)
            .background(cap.fill(fillStyle))
            .overlay {
                if recording {
                    cap.strokeBorder(Color.accentColor, lineWidth: 1.5)
                    RoundedRectangle(cornerRadius: (Design.KeyCap.radius + 3) * k, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 3).padding(-3)
                } else {
                    cap.strokeBorder(Design.edge(contrast), lineWidth: 1)
                }
            }
            .fixedSize()
    }

    private var textStyle: AnyShapeStyle {
        if let onAccent { return AnyShapeStyle(onAccent) }
        return dim ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary.opacity(Design.KeyCap.text))
    }

    private var fillStyle: AnyShapeStyle {
        if onAccent != nil { return AnyShapeStyle(.white.opacity(Design.KeyCap.onAccent)) }
        return AnyShapeStyle(.primary.opacity(recording ? 0 : hovering ? Design.KeyCap.hover : fill))
    }
}

private struct KeyCapFillKey: EnvironmentKey { static let defaultValue = Design.KeyCap.rest }

extension EnvironmentValues {
    /// The key cap fill at rest on the surface below: `Design.KeyCap.fill(on:)`.
    var keyCapFill: Double {
        get { self[KeyCapFillKey.self] }
        set { self[KeyCapFillKey.self] = newValue }
    }
}

/// A short status in its color: "Allowed", "Not allowed", "Installed".
struct StatusBadge: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label { Text(text) } icon: { Image(systemName: symbol) }
            .font(Design.secondary.weight(.medium))
            .foregroundStyle(tint)
            .labelStyle(BadgeLabelStyle())
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.14)))
    }

    private struct BadgeLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 3) { configuration.icon; configuration.title }
        }
    }
}

/// AppKit's search field: the rounded field with a magnifier and a clear button.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var prompt = "Search"
    let label: String // what VoiceOver says the field searches

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.setAccessibilityLabel(label)
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.focusRingType = .default
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func controlTextDidChange(_ note: Notification) {
            if let field = note.object as? NSSearchField { text.wrappedValue = field.stringValue }
        }
    }
}
