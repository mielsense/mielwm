import AppKit
import MielCore
import MielSystem
import SwiftUI

struct AdvancedPane: View {
    @EnvironmentObject var model: SettingsModel

    var body: some View {
        Form {
            Section { PaneHeader(pane: .advanced) }
            if !model.errors.isEmpty {
                Section {
                    HStack(alignment: .top, spacing: Design.Space.s + 2) {
                        IconTile("exclamationmark.triangle.fill", tint: Design.Tint.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Some settings could not be read").font(Design.row)
                            ForEach(model.errors, id: \.self) { Text($0).font(Design.secondary).foregroundStyle(.secondary).textSelection(.enabled) }
                            Text("mielwm uses the defaults for those.").font(Design.secondary).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                SettingsRow("Config file", subtitle: (model.paths.config.path as NSString).abbreviatingWithTildeInPath,
                            icon: IconTile("doc.text.fill", tint: Design.Tint.gray)) {
                    HStack(spacing: Design.Space.s) {
                        Button("Show in Finder") { revealConfigFile(model.paths.config) }
                        Button("Open") { openConfigFile(model.paths.config) }
                    }
                }
                SettingsRow("Command-line tool", subtitle: cliNote, icon: IconTile("terminal.fill", tint: Design.Tint.graphite)) {
                    HStack(spacing: Design.Space.s) {
                        switch model.cliStatus {
                        case .installed:
                            StatusBadge(text: "Installed", symbol: "checkmark.circle.fill", tint: .green)
                            Button("Remove") { model.cliStatus = CLITool.remove() }
                        default:
                            Button("Install") { install() }
                        }
                    }
                }
            } footer: {
                Text("Settings are saved there as you change them, and edits to the file show up here. Some settings exist only in the file. [Configuration file](https://wm.miel.my/docs/configuration) lists them all.").settingsFooter()
            }
            Section {
                SettingsRow("Reset all settings", subtitle: "Every setting and shortcut back to its default.",
                            icon: IconTile("arrow.counterclockwise", tint: Design.Tint.red)) {
                    Button("Reset…") { model.confirmReset = true }
                }
            }
        }
        .confirmationDialog("Reset all settings?", isPresented: $model.confirmReset) {
            Button("Reset", role: .destructive) { model.resetAll() }
        } message: {
            Text("config.json goes to the Trash, so you can get it back.")
        }
    }

    private var cliNote: String {
        switch model.cliStatus {
        case let .installed(at): "Installed as \(at). Try \"\(CLITool.name) overview\"."
        case let .taken(at): "\(at) is another file. Install replaces it."
        case .missing: "Links \"\(CLITool.name)\" into ~/.local/bin, to drive mielwm from Terminal."
        }
    }

    private func install() {
        do { model.cliStatus = try CLITool.install() } catch { model.problem = "Can't install the command-line tool: \(error.localizedDescription)" }
    }
}

/// Opens config.json, making an empty one first if needed.
func openConfigFile(_ url: URL) {
    if !FileManager.default.fileExists(atPath: url.path) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("{\n}\n".utf8).write(to: url)
    }
    NSWorkspace.shared.open(url)
}

/// Shows config.json in Finder, or its folder while there is no file yet.
func revealConfigFile(_ url: URL) {
    if FileManager.default.fileExists(atPath: url.path) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    } else {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        NSWorkspace.shared.open(url.deletingLastPathComponent())
    }
}
