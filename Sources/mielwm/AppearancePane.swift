import AppKit
import MielCore
import MielSystem
import SwiftUI

struct AppearancePane: View {
    @EnvironmentObject var model: SettingsModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let look = model.settings.look
        Form {
            Section { PaneHeader(pane: .appearance) }
            Section {
                AppearancePreviewView(settings: model.settings, dark: colorScheme == .dark, preview: model.preview)
            } footer: {
                Text("The canvas as you set it. The overview shows each change right away.").settingsFooter()
            }
            Section("Theme") {
                AccentPicker()
                // Slot: the "Glass style" picker (appearance:glass, Liquid or Frosted) from
                // feat/on-screen-indicators goes here, as a VisualPicker over Design.Glass.
            }
            Section("Background") {
                Toggle("Show the desktop picture", isOn: model.flag("wallpaper"))
                LabeledSlider("Dim", value: model.number("canvas:background_dim"), in: 0 ... 0.9) { "\(Int(($0 * 100).rounded()))%" }
                Toggle("Blur", isOn: model.flag("blur"))
                    .disabled(!look.wallpaperEnabled)
                LabeledSlider("Blur amount", value: model.number("blur_strength"), in: 0 ... 1) { "\(Int(($0 * 100).rounded()))%" }
                    .disabled(!look.wallpaperEnabled || !look.blur)
            }
            Section("Grid") {
                Toggle("Show the grid", isOn: model.flag("canvas:grid_enabled"))
                VisualPicker(title: "Style", selection: model.text("canvas:grid_style"), options: ["dots", "lines"], name: { $0 == "dots" ? "Dots" : "Lines" }) {
                    GridThumbnail(dots: $0 == "dots")
                }
                .disabled(!look.gridEnabled)
                .opacity(look.gridEnabled ? 1 : 0.5)
                LabeledSlider("Opacity", value: model.number("canvas:grid_opacity"), in: 0 ... 0.5) { "\(Int(($0 * 100).rounded()))%" }
                    .disabled(!look.gridEnabled)
            }
            Section("Windows") {
                LabeledSlider("Corner rounding", value: model.number("window:rounding"), in: 0 ... 40) { "\(Int($0.rounded())) pt" }
                Toggle("Shadows", isOn: model.flag("window:shadow"))
            }
        }
    }
}

/// The canvas grid: dots or lines over the dark canvas.
struct GridThumbnail: View {
    let dots: Bool

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.16)))
            let step: CGFloat = 8
            for x in stride(from: step / 2, to: size.width, by: step) {
                for y in stride(from: step / 2, to: size.height, by: step) where dots {
                    context.fill(Path(ellipseIn: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8)), with: .color(.white.opacity(0.45)))
                }
                if !dots { context.fill(Path(CGRect(x: x, y: 0, width: 0.6, height: size.height)), with: .color(.white.opacity(0.3))) }
            }
            if !dots {
                for y in stride(from: step / 2, to: size.height, by: step) {
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.6)), with: .color(.white.opacity(0.3)))
                }
            }
        }
    }
}

/// The system accent, the presets and a color well, as swatches; the chosen
/// one has a ring and a dot, and its name shows beside the title.
struct AccentPicker: View {
    @EnvironmentObject var model: SettingsModel

    var body: some View {
        let accent = model.settings.accent.lowercased()
        let presets = accentPresets.filter { $0.value != "auto" }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Accent color")
                Spacer()
                Text(accent == "auto" ? "Automatic" : presets.first { $0.name.lowercased() == accent || $0.value == accent }?.name ?? "Custom")
                    .foregroundStyle(.secondary)
                AccentWell(color: NSColor(hex: hexString(model.settings.resolvedLook(systemAccent: Controller.systemAccent()).accent))) { c in
                    guard let c = c.usingColorSpace(.sRGB) else { return }
                    model.set("navigator:accent", .text(hexString(RGB(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)))))
                }
                .frame(width: 44, height: 22)
                .help("Choose any color")
            }
            HStack(spacing: 0) {
                Swatch(name: "Automatic", detail: "Follows the accent color in System Settings", selected: accent == "auto",
                       fill: AnyShapeStyle(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center)),
                       light: false) { model.set("navigator:accent", .text("auto")) }
                ForEach(presets, id: \.name) { p in
                    let color = NSColor(hex: p.value)
                    Swatch(name: p.name, selected: accent == p.name.lowercased() || accent == p.value, fill: AnyShapeStyle(Color(nsColor: color)),
                           light: color.isLight) { model.set("navigator:accent", .text(p.name.lowercased())) }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// AppKit's small color well: a swatch with a chevron that opens the system's colors.
struct AccentWell: NSViewRepresentable {
    let color: NSColor
    let changed: (NSColor) -> Void

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell(style: .minimal)
        well.supportsAlpha = false
        well.target = context.coordinator
        well.action = #selector(Coordinator.changed(_:))
        well.setAccessibilityLabel("Custom accent color")
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        context.coordinator.changed = changed
        if !well.isActive, well.color != color { well.color = color } // not while the color panel drives it
    }

    func makeCoordinator() -> Coordinator { Coordinator(changed) }

    final class Coordinator: NSObject {
        var changed: (NSColor) -> Void
        init(_ changed: @escaping (NSColor) -> Void) { self.changed = changed }
        @objc func changed(_ well: NSColorWell) { changed(well.color) }
    }
}

struct Swatch: View {
    let name: String
    var detail: String?
    let selected: Bool
    let fill: AnyShapeStyle
    let light: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // As System Settings marks the chosen color: a ring of the same color around it.
            ZStack {
                Circle().fill(fill).frame(width: 16, height: 16)
                Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5).frame(width: 16, height: 16)
                if selected {
                    Circle().strokeBorder(light ? AnyShapeStyle(Color.secondary) : fill, lineWidth: 2).frame(width: 22, height: 22)
                }
            }
            .frame(width: 24, height: 24)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(detail.map { "\(name): \($0)" } ?? name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

extension NSColor {
    convenience init(hex: String) {
        let c = parseHexColor(hex) ?? RGB(1, 1, 1)
        self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
    }

    /// Light enough that white on it would not read.
    var isLight: Bool {
        guard let c = usingColorSpace(.sRGB) else { return false }
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent > 0.8
    }
}
