import AppKit
import MielCore
import MielSystem
import SwiftUI

struct LayoutPane: View {
    @EnvironmentObject var model: SettingsModel
    private let aeroSpaceURL = AeroSpaceImport.standardURL()

    var body: some View {
        let s = model.settings
        Form {
            Section {
                Picker("Layout", selection: Binding(get: { s.defaultLayout }, set: { model.set("layout:default", .text($0.rawValue)) })) {
                    Text("Tiles").tag(LayoutMode.tiles)
                    Text("Stack").tag(LayoutMode.stack)
                    Text("Floating").tag(LayoutMode.floating)
                }
                Picker("Orientation", selection: Binding(get: { s.orientation }, set: { model.set("layout:orientation", .text($0.rawValue)) })) {
                    Text("Automatic").tag(TileOrientation.auto)
                    Text("Side by side").tag(TileOrientation.horizontal)
                    Text("Above each other").tag(TileOrientation.vertical)
                }
            } header: {
                Text("New windows")
            } footer: {
                Text("Automatic puts tiles side by side on a wide display and above each other on a tall one.").settingsFooter()
            }
            Section("Gaps") {
                GapDiagram(settings: s, screen: model.screen).frame(height: 132).frame(maxWidth: .infinity).padding(.vertical, 4)
                GapField(title: "Between windows, side by side", key: "gaps:inner_horizontal")
                GapField(title: "Between windows, above each other", key: "gaps:inner_vertical")
                GapField(title: "Left edge", key: "gaps:outer_left")
                GapField(title: "Right edge", key: "gaps:outer_right")
                GapField(title: "Bottom edge", key: "gaps:outer_bottom")
                Picker(selection: Binding(get: { s.topGapMode }, set: setTopGapMode)) {
                    Text("Automatic").tag(TopGapMode.auto)
                    Text("Same as other edges").tag(TopGapMode.same)
                    Text("Custom").tag(TopGapMode.custom)
                } label: {
                    Text("Top edge")
                    Text(topEdgeNote).monospacedDigit()
                }
                GapField(title: s.topGapMode == .custom ? "Top gap, built-in display" : "Top gap", key: "gaps:outer_top")
                if s.topGapMode == .custom { GapField(title: "Top gap, other displays", key: "gaps:outer_top_external") }
            }
            Section {
                Toggle(isOn: model.flag("input:swipe_workspaces")) {
                    Text("Swipe between workspaces")
                    Text("Three fingers left or right on the trackpad go to the next or previous workspace, with a click you can feel.")
                }
                if s.swipeWorkspaces, systemThreeFingerSwipe() {
                    LabeledContent {
                        Button("Open Trackpad Settings…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)
                        }
                    } label: {
                        Label("macOS swipes with three fingers too", systemImage: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                        Text("Its swipe between full-screen apps bounces the screen as you swipe. In More Gestures, set it to four fingers.")
                    }
                }
            } header: {
                Text("Trackpad")
            }
            Section {
                ForEach(parseWorkspaceRules(s.workspaceRules).sorted { ($0.value, AppInfo(bundleID: $0.key).name) < ($1.value, AppInfo(bundleID: $1.key).name) }, id: \.key) { id, number in
                    AppRow(bundleID: id, remove: { setRule(id, nil) }) {
                        Picker("Workspace", selection: Binding(get: { number }, set: { setRule(id, $0) })) {
                            ForEach(1 ... 9, id: \.self) { Text("Workspace \($0)").tag($0) }
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
                Toggle(isOn: Binding(get: { s.barik }, set: { model.onBarik($0) })) {
                    Text("Work with Barik")
                    Text(model.barikAvailable ? "Barik's menu bar shows mielwm's workspaces and windows. mielwm asks before it edits Barik's config and relaunches Barik."
                        : "Works when mielwm runs from mielwm.app.")
                }
                .disabled(!model.barikAvailable)
                LabeledContent {
                    Button("Import…") { readAeroSpace() }.disabled(aeroSpaceURL == nil)
                } label: {
                    Text("Import from AeroSpace")
                    Text(aeroSpaceURL.map { "Gaps, layout, rules and shortcuts from \(($0.path as NSString).abbreviatingWithTildeInPath)." }
                        ?? "No AeroSpace config found.")
                }
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

    /// What the top edge gets: in Automatic, the bar found on the display the window is on.
    private var topEdgeNote: String {
        switch model.settings.topGapMode {
        case .auto: model.screen?.topBar.map { "\($0.owner), \(Int($0.height)) pt. Its height is added to the top gap." }
            ?? "No bar found on this display."
        case .same: "The top gap only, on every display."
        case .custom: "Your own top gap on displays other than the built-in one."
        }
    }

    private func setTopGapMode(_ mode: TopGapMode) {
        // Custom's number is for the displays other than the built-in one: it starts from what they have now,
        // the most of them, so a display with a bar keeps its room.
        let custom = model.screens.filter { !$0.isBuiltIn }.map(model.settings.topGap).max() ?? model.settings.gapOuterTopExternal
        model.set("gaps:outer_top_external", mode == .custom ? .number(custom) : .text(mode.rawValue))
    }

    private func readAeroSpace() {
        guard let url = aeroSpaceURL else { return }
        do { model.aeroSpaceFound = AeroSpaceImport(toml: try String(contentsOf: url, encoding: .utf8)) } catch {
            model.problem = "Can't read \(url.lastPathComponent): \(error.localizedDescription)"
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

/// A number of points: a field and a stepper.
struct GapField: View {
    let title: String
    let key: String
    @EnvironmentObject var model: SettingsModel

    var body: some View {
        let value = model.number(key)
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: value, format: .number.precision(.fractionLength(0)))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                Stepper(title, value: value, in: 0 ... 400, step: 2).labelsHidden()
                Text("pt").foregroundStyle(.secondary).frame(width: 16, alignment: .leading)
            }
        }
    }
}

/// A display with two tiles, drawn with the gaps as they are set.
struct GapDiagram: View {
    let settings: MielCore.Settings
    let screen: ScreenInfo? // the top gap and status bar on this display

    private var topGap: Double { screen.map(settings.topGap) ?? settings.gapOuterTop }

    var body: some View {
        Canvas { context, size in
            let w = min(size.width, (size.height - 8) * 1.6)
            let screen = CGRect(x: (size.width - w) / 2, y: 4, width: w, height: size.height - 8)
            let k = 0.5 // half size, so the gaps read at a glance
            context.fill(Path(roundedRect: screen, cornerRadius: 7), with: .color(.secondary.opacity(0.1)))
            context.stroke(Path(roundedRect: screen.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 7), with: .color(.secondary.opacity(0.35)), lineWidth: 1)
            let s = settings, top = topGap
            if s.topGapMode == .auto, let bar = self.screen?.topBar { // the status bar the gap makes room for
                let band = CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: bar.height * k)
                context.fill(Path(roundedRect: band, cornerRadii: RectangleCornerRadii(topLeading: 7, topTrailing: 7)), with: .color(.secondary.opacity(0.25)))
            }
            let area = CGRect(x: screen.minX + s.gapOuterLeft * k, y: screen.minY + top * k,
                              width: screen.width - (s.gapOuterLeft + s.gapOuterRight) * k,
                              height: screen.height - (top + s.gapOuterBottom) * k)
            guard area.width > 8, area.height > 8 else { return }
            let tileWidth = max(1, (area.width - s.gapInnerHorizontal * k) / 2)
            let rightHeight = max(1, (area.height - s.gapInnerVertical * k) / 2)
            let tiles = [CGRect(x: area.minX, y: area.minY, width: tileWidth, height: area.height),
                         CGRect(x: area.maxX - tileWidth, y: area.minY, width: tileWidth, height: rightHeight),
                         CGRect(x: area.maxX - tileWidth, y: area.maxY - rightHeight, width: tileWidth, height: rightHeight)]
            for tile in tiles {
                context.fill(Path(roundedRect: tile, cornerRadius: 4), with: .color(.accentColor.opacity(0.2)))
                context.stroke(Path(roundedRect: tile.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 4), with: .color(.accentColor.opacity(0.75)), lineWidth: 1)
            }
        }
        .accessibilityLabel("A display with three windows and the gaps around them, \(Int(topGap)) pt at the top")
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
        HStack(spacing: 8) {
            Image(nsImage: app.icon).resizable().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                if !app.installed { Text("Not installed").font(.caption).foregroundStyle(.secondary) }
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

struct AppInfo {
    let name: String
    let icon: NSImage
    let installed: Bool
    @MainActor private static var known: [String: AppInfo] = [:] // views ask on every redraw; a lookup reads the disk

    @MainActor init(bundleID: String) {
        if let info = Self.known[bundleID] {
            self = info
            return
        }
        self.init(looking: bundleID)
        if installed { Self.known[bundleID] = self } // an app not found may be installed later
    }

    private init(looking bundleID: String) {
        // The running copy first: Launch Services may know an old one (a renamed backup) under the same id.
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        if let url = running?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            // The app's own name, not the file's: a copy renamed on disk keeps its real name.
            let bundle = Bundle(url: url)
            name = running?.localizedName ?? bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            icon = NSWorkspace.shared.icon(forFile: url.path)
            installed = true
        } else {
            name = bundleID
            icon = NSWorkspace.shared.icon(for: .applicationBundle)
            installed = false
        }
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

/// macOS's own three-finger swipe between full-screen apps (Trackpad > More Gestures), built in or Magic Trackpad.
func systemThreeFingerSwipe() -> Bool {
    ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"].contains { domain in
        CFPreferencesAppSynchronize(domain as CFString)
        return (CFPreferencesCopyAppValue("TrackpadThreeFingerHorizSwipeGesture" as CFString, domain as CFString) as? Int) == 2
    }
}
