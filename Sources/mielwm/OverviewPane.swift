import MielCore
import SwiftUI

/// Settings > Overview.
struct OverviewPane: View {
    @EnvironmentObject var model: SettingsModel

    var body: some View {
        let look = model.settings.look
        Form {
            Section { PaneHeader(pane: .overview) }
            Section {
                LabeledSlider("Zoomed-out level", value: model.number("canvas:initial_zoom"), in: 0.1 ... 0.95) { "\(Int(($0 * 100).rounded()))%" }
                Toggle("Show window names", isOn: model.flag("navigator:labels"))
                Toggle(isOn: model.flag("canvas:minimap_enabled")) {
                    Text("Show the minimap")
                    Text("A map of the whole canvas in a corner of the overview.")
                }
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
        }
    }
}
