import AppKit
import MielCore
import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    @EnvironmentObject var model: SettingsModel
    private let bundled = Bundle.main.bundleURL.pathExtension == "app"

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { model.loginStatus == .enabled || model.loginStatus == .requiresApproval }, set: setLogin)) {
                    Text("Open at login")
                    if !bundled {
                        Text("Works when mielwm runs from mielwm.app.")
                    } else if model.loginStatus == .requiresApproval {
                        Text("Allow mielwm in System Settings > General > Login Items.")
                    }
                }
                .disabled(!bundled)
                Toggle(isOn: model.flag("menubar:workspaces")) {
                    Text("Show workspaces in the menu bar")
                    Text("The numbers of the workspaces that have windows, with the current one filled.")
                }
            }
            Section("Overview") {
                LabeledSlider("Zoomed-out level", value: model.number("canvas:initial_zoom"), in: 0.1 ... 0.95) { "\(Int(($0 * 100).rounded()))%" }
                Toggle(isOn: model.flag("navigator:pointer")) {
                    Text("Use the pointer")
                    Text("Click a window to go to it, drag to move windows or the canvas, scroll to zoom.")
                }
            }
            Section("Animation") {
                Toggle("Animate the camera", isOn: model.flag("animation:enabled"))
                // Doubling steps: 1× sits in the middle, from 4× slower to 4× faster.
                LabeledSlider("Speed", value: Binding(get: { log2(model.settings.animationSpeed) }, set: { model.set("animation:speed", .number(pow(2, $0))) }),
                              in: -2 ... 2) { String(format: pow(2, $0) < 0.95 ? "%.2g×" : "%.1f×", pow(2, $0)).replacingOccurrences(of: ".0×", with: "×") }
                    .disabled(!model.settings.animationEnabled)
            }
            Section {
                Toggle(isOn: model.flag("canvas:remember_layout")) {
                    Text("Remember where windows are")
                    Text("After a restart, windows come back to their places on the canvas.")
                }
            }
        }
    }

    private func setLogin(_ on: Bool) {
        do { try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() } catch {
            model.problem = "Open at login: \(error.localizedDescription)"
        }
        model.loginStatus = SMAppService.mainApp.status
    }
}
