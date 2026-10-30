import AppKit
import MielCore
import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    @EnvironmentObject var model: SettingsModel
    private let bundled = Bundle.main.bundleURL.pathExtension == "app"

    var body: some View {
        Form {
            Section { PaneHeader(pane: .general) }
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
                Toggle(isOn: model.flag("canvas:remember_layout")) {
                    Text("Remember where windows are")
                    Text("After a restart, windows come back to their places on the canvas.")
                }
            }
            Section("Animation") {
                Toggle("Animate the camera", isOn: model.flag("animation:enabled"))
                // Doubling steps: 1× sits in the middle, from 4× slower to 4× faster.
                LabeledSlider("Speed", value: Binding(get: { log2(model.settings.animationSpeed) }, set: { model.set("animation:speed", .number(pow(2, $0))) }),
                              in: -2 ... 2, format: doublingText)
                    .disabled(!model.settings.animationEnabled)
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
