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
            Section {
                AppearancePreviewView(settings: model.settings, dark: colorScheme == .dark, preview: model.preview)
                AccentPicker()
                // Without Liquid glass the panels are frosted, whatever the stored value (a config synced from a newer Mac).
                Picker(selection: Controller.liquidGlassAvailable ? model.text("appearance:glass") : .constant(GlassStyle.frosted.rawValue)) {
                    Text("Liquid glass").tag(GlassStyle.liquid.rawValue)
                    Text("Frosted").tag(GlassStyle.frosted.rawValue)
                } label: {
                    Text("Glass style")
                    if !Controller.liquidGlassAvailable { Text("Liquid glass needs macOS 26.") }
                }
                .disabled(!Controller.liquidGlassAvailable)
            } footer: {
                Text("The canvas as you set it. The overview shows the change right away.").settingsFooter()
            }
            Section("Lens") {
                Toggle(isOn: model.flag("distortion:enabled")) {
                    Text("Bend the edges")
                    Text("The zoomed-out canvas curves away at the edges of the screen, like through a lens.")
                }
                LabeledSlider("Strength", value: model.number("distortion:strength"), in: 0 ... 0.5) { "\(Int(($0 * 200).rounded()))%" }
                    .disabled(!look.lensEnabled)
                LabeledSlider("Magnification", value: model.number("distortion:edge_scale"), in: 1 ... 1.5) { "\(Int((($0 - 1) * 200).rounded()))%" }
                    .disabled(!look.lensEnabled)
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
                Picker("Style", selection: model.text("canvas:grid_style")) {
                    Text("Dots").tag("dots")
                    Text("Lines").tag("lines")
                }
                .disabled(!look.gridEnabled)
                LabeledSlider("Opacity", value: model.number("canvas:grid_opacity"), in: 0 ... 0.5) { "\(Int(($0 * 100).rounded()))%" }
                    .disabled(!look.gridEnabled)
            }
            Section("Windows") {
                LabeledSlider("Corner rounding", value: model.number("window:rounding"), in: 0 ... 40) { "\(Int($0.rounded())) pt" }
                Toggle("Shadows", isOn: model.flag("window:shadow"))
                Toggle("Show window names", isOn: model.flag("navigator:labels"))
                Toggle(isOn: model.flag("canvas:minimap_enabled")) {
                    Text("Show the minimap")
                    Text("A map of the whole canvas in a corner of the overview.")
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
            HStack(spacing: 2) {
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
            ZStack {
                Circle().fill(fill).frame(width: 16, height: 16)
                Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5).frame(width: 16, height: 16)
                if selected {
                    Circle().fill(light ? Color.black.opacity(0.55) : .white).frame(width: 6, height: 6)
                    Circle().strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1.5).frame(width: 21, height: 21)
                }
            }
            .frame(width: 22, height: 22)
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
