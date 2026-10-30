import AppKit
import MielCore
import SwiftUI

struct WindowsPane: View {
    @EnvironmentObject var model: SettingsModel

    var body: some View {
        let s = model.settings
        Form {
            Section { PaneHeader(pane: .windows) }
            Section {
                ForEach(parseAppList(s.floatingApps), id: \.self) { id in
                    AppRow(bundleID: id) { removeFloating(id) }
                }
                AddAppMenu { addFloating($0) }
            } header: {
                Text("Floating apps")
            } footer: {
                Text("Windows of these apps float above the tiles.").settingsFooter()
            }
            Section {
                ForEach(parseWorkspaceRules(s.workspaceRules).sorted { ($0.value, AppInfo(bundleID: $0.key).name) < ($1.value, AppInfo(bundleID: $1.key).name) }, id: \.key) { id, number in
                    AppRow(bundleID: id, remove: { setRule(id, nil) }) {
                        Picker("Workspace", selection: Binding(get: { number }, set: { setRule(id, $0) })) {
                            // A rule from the config file may name a workspace past 9: it stays a choice.
                            ForEach(1 ... max(9, number), id: \.self) { Text("Workspace \($0)").tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                AddAppMenu { setRule($0, 1) }
            } header: {
                Text("Workspace rules")
            } footer: {
                Text("New windows of these apps open on their workspace.").settingsFooter()
            }
        }
    }

    private func addFloating(_ id: String) {
        var list = parseAppList(model.settings.floatingApps)
        guard !list.contains(id) else { return }
        list.append(id)
        model.set("layout:floating_apps", .text(list.joined(separator: ",")))
    }

    private func removeFloating(_ id: String) {
        model.set("layout:floating_apps", .text(parseAppList(model.settings.floatingApps).filter { $0 != id }.joined(separator: ",")))
    }

    private func setRule(_ id: String, _ number: Int?) {
        var rules = parseWorkspaceRules(model.settings.workspaceRules)
        rules[id] = number
        model.set("layout:workspace_rules", .text(formatWorkspaceRules(rules)))
    }
}

/// An app by bundle id: icon, name, then `trailing` and a remove button.
struct AppRow<Trailing: View>: View {
    let bundleID: String
    let remove: () -> Void
    @ViewBuilder var trailing: Trailing

    init(bundleID: String, remove: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.bundleID = bundleID
        self.remove = remove
        self.trailing = trailing()
    }

    var body: some View {
        let app = AppInfo(bundleID: bundleID)
        HStack(spacing: Design.Space.s + 2) {
            IconTile(image: app.icon, size: Design.Tile.row)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                if !app.installed { Text("Not installed").font(Design.secondary).foregroundStyle(.secondary) }
            }
            Spacer()
            trailing
            Button(action: remove) { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary).imageScale(.medium) }
                .buttonStyle(.borderless)
                .help("Remove \(app.name)")
                .accessibilityLabel("Remove \(app.name)")
        }
        .help(bundleID)
    }
}

/// "Add app": a running app, or any app from Finder.
struct AddAppMenu: View {
    let add: (String) -> Void

    var body: some View {
        Menu {
            let apps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
                .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
            Section("Open apps") {
                ForEach(apps, id: \.processIdentifier) { app in
                    Button(app.localizedName ?? app.bundleIdentifier!) { add(app.bundleIdentifier!) }
                }
            }
            Divider()
            Button("Choose an app…") { choose() }
        } label: {
            Label("Add app", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        add(id)
    }
}

