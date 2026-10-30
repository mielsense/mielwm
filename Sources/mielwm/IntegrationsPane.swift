import AppKit
import MielCore
import SwiftUI

struct IntegrationsPane: View {
    @EnvironmentObject var model: SettingsModel
    private let aeroSpaceURL = AeroSpaceImport.standardURL()

    var body: some View {
        Form {
            Section { PaneHeader(pane: .integrations) }
            Section {
                SettingsRow("Work with AeroSpace-compatible apps",
                            subtitle: model.barikAvailable ? "Runs a small helper named AeroSpace, so menu bars and tools made for AeroSpace show mielwm's workspaces through its aerospace command. For a menu bar like Barik, mielwm also points its config at that command, after asking."
                                : "Works when mielwm runs from mielwm.app.",
                            icon: IconTile("menubar.dock.rectangle", tint: Design.Tint.graphite)) {
                    Toggle("Work with AeroSpace-compatible apps", isOn: Binding(get: { model.settings.barik }, set: { model.onBarik($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!model.barikAvailable)
                }
            } header: {
                Text("Menu bars and tools")
            }
            Section {
                SettingsRow("Import from AeroSpace",
                            subtitle: aeroSpaceURL.map { "Gaps, layout, rules and shortcuts from \(($0.path as NSString).abbreviatingWithTildeInPath)." }
                                ?? "No AeroSpace config found.",
                            icon: IconTile("square.and.arrow.down.fill", tint: Design.Tint.blue)) {
                    Button("Import…") { readAeroSpace() }.disabled(aeroSpaceURL == nil)
                }
            } header: {
                Text("AeroSpace")
            } footer: {
                Text("You see what will change before anything is applied.").settingsFooter()
            }
        }
        .alert(model.aeroSpaceFound.map { $0.isEmpty ? "Nothing to import" : "Import from AeroSpace?" } ?? "",
               isPresented: Binding(get: { model.aeroSpaceFound != nil }, set: { if !$0 { model.aeroSpaceFound = nil } })) {
            if let f = model.aeroSpaceFound, !f.isEmpty {
                Button("Import") { model.apply(f.changes(onto: model.settings, keys: true)); model.aeroSpaceFound = nil }
            }
            Button(model.aeroSpaceFound?.isEmpty == false ? "Cancel" : "OK", role: .cancel) { model.aeroSpaceFound = nil }
        } message: {
            Text(model.aeroSpaceFound.map { $0.isEmpty ? "The AeroSpace config has no gaps, layout, rules or shortcuts mielwm can use." : $0.summary { AppInfo(bundleID: $0).name }.joined(separator: "\n\n") } ?? "")
        }
    }

    private func readAeroSpace() {
        guard let url = aeroSpaceURL else { return }
        do { model.aeroSpaceFound = AeroSpaceImport(toml: try String(contentsOf: url, encoding: .utf8)) } catch {
            model.problem = "Can't read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}
