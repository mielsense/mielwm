import AppKit
import MielCore
import MielSystem
import SwiftUI

struct AdvancedPane: View {
    @EnvironmentObject var model: SettingsModel

    var body: some View {
        Form {
            if !model.errors.isEmpty {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Some settings could not be read")
                            ForEach(model.errors, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                            Text("mielwm uses the defaults for those.").font(.callout).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    }
                }
            }
            Section {
                LabeledContent {
                    HStack {
                        Button("Show in Finder") { revealConfigFile(model.paths.config) }
                        Button("Open") { openConfigFile(model.paths.config) }
                    }
                } label: {
                    Text("Config file")
                    Text((model.paths.config.path as NSString).abbreviatingWithTildeInPath)
                }
            } footer: {
                Text("Settings are saved there as you change them, and edits to the file show up here. Some settings exist only in the file; the README lists them.").settingsFooter()
            }
            Section {
                LabeledContent {
                    switch model.cliStatus {
                    case .installed: Button("Remove") { model.cliStatus = CLITool.remove() }
                    default: Button("Install") { install() }
                    }
                } label: {
                    Text("Command-line tool")
                    switch model.cliStatus {
                    case let .installed(at): Text("Installed as \(at). Try \"\(CLITool.name) overview\".")
                    case let .taken(at): Text("\(at) is another file. Install replaces it.")
                    case .missing: Text("Links \"\(CLITool.name)\" into ~/.local/bin, to drive mielwm from Terminal.")
                    }
                }
            }
            Section {
                LabeledContent {
                    Button("Reset…") { model.confirmReset = true }
                } label: {
                    Text("Reset all settings")
                    Text("Every setting and shortcut back to its default.")
                }
            }
            Section {
                LabeledContent("Version", value: appVersion)
            }
        }
        .confirmationDialog("Reset all settings?", isPresented: $model.confirmReset) {
            Button("Reset", role: .destructive) { model.resetAll() }
        } message: {
            Text("config.json goes to the Trash, so you can get it back.")
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
