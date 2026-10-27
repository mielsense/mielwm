import AppKit
import Combine
import MielCore
import MielSystem
import ServiceManagement
import SwiftUI

/// What the Settings window shows and edits: config.json as Settings. A
/// change reaches the running canvas at once (`onLive`) and config.json a
/// moment later, so a slider being dragged does not write on every step.
@MainActor
final class SettingsModel: ObservableObject {
    let paths: ConfigPaths
    @Published private(set) var settings: MielCore.Settings
    @Published private(set) var errors: [String] // what config.json got wrong
    @Published var problem: String? // a write that failed, shown as an alert
    @Published var recording: ShortcutSlot? { didSet { recordingChanged() } } // the recorder that listens
    @Published var held: Modifiers = [] // modifiers down while recording
    var keyMonitor: Any?
    // View state lives here: the Command Line Tools have no SwiftUI macros, so no @State.
    @Published var pane: SettingsPane {
        didSet {
            scrolled = false
            if remembersPane { UserDefaults.standard.set(pane.rawValue, forKey: "settingsPane") }
        }
    }
    @Published var loginStatus = SMAppService.mainApp.status
    @Published var aeroSpaceFound: AeroSpaceImport?
    @Published var confirmReset = false
    @Published var confirmRestoreShortcuts = false
    @Published var conflict: ShortcutConflict?
    @Published var expanded: Set<ShortcutFamily> = [] // custom families showing their keys
    @Published var scrolled = false // the pane is scrolled: a line under the title bar
    @Published var cliStatus = CLITool.status()
    /// The Appearance pane's canvas, made on the first visit; its GPU textures go when the window closes.
    var preview: AppearancePreview {
        if let madePreview { return madePreview }
        let made = AppearancePreview()
        madePreview = made
        return made
    }
    private(set) var madePreview: AppearancePreview?
    /// After every write: the canvas reloads config.json.
    var onWrite: () -> Void = {}
    /// Every change, before it is written.
    var onLive: (MielCore.Settings) -> Void = { _ in }
    /// While a recorder listens, the canvas's shortcuts must let keys through.
    var onRecording: (Bool) -> Void = { _ in }
    let remembersPane: Bool
    private var pending: [String: SettingValue?] = [:]
    private var flushWork: DispatchWorkItem?
    private var stamp: [Date?] = []
    private var watcher: FileWatcher?

    init(paths: ConfigPaths = .standard(), remembersPane: Bool = true) {
        self.paths = paths
        self.remembersPane = remembersPane
        let loaded = loadSettings(paths)
        settings = loaded.settings
        errors = loaded.errors
        pane = remembersPane ? UserDefaults.standard.string(forKey: "settingsPane").flatMap(SettingsPane.init) ?? .general : .general
        stamp = stamps()
    }

    /// Picks up edits made elsewhere (the file, the canvas).
    func reload() {
        guard pending.isEmpty else { return }
        stamp = stamps()
        let loaded = loadSettings(paths)
        if loaded.settings != settings { settings = loaded.settings }
        if loaded.errors != errors { errors = loaded.errors }
    }

    /// While the window is open, edits to the files show up at once.
    func watch(_ on: Bool) {
        watcher?.stop()
        watcher = nil
        guard on else { return }
        watcher = FileWatcher([paths.config]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.stamps() != self.stamp else { return }
                self.reload()
            }
        }
    }

    private func stamps() -> [Date?] {
        [paths.config].map { (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date }
    }

    func set(_ key: String, _ value: SettingValue) {
        guard settings.set(value, forKey: key) == nil else { return }
        pending[key] = Settings.entry(key, value)
        onLive(settings)
        flushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.flush() } }
        flushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// Writes `changes` (and anything waiting) now.
    func apply(_ changes: [String: SettingValue?]) {
        pending.merge(changes) { _, new in new }
        flush()
    }

    func flush() {
        flushWork?.cancel()
        guard !pending.isEmpty else { return }
        do { try updateConfig(pending, paths: paths) } catch { problem = "\(error)" }
        pending = [:]
        reload()
        onWrite()
    }

    /// Puts config.json in the Trash: every setting back to its default.
    func resetAll() {
        flushWork?.cancel()
        pending = [:]
        for url in [paths.config] where FileManager.default.fileExists(atPath: url.path) {
            do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } catch { problem = "\(error.localizedDescription)" }
        }
        reload()
        onWrite()
    }

    // MARK: Bindings for controls

    func flag(_ key: String) -> Binding<Bool> {
        Binding(get: { if case let .flag(b)? = self.settings.value(forKey: key) { b } else { false } },
                set: { self.set(key, .flag($0)) })
    }

    func number(_ key: String) -> Binding<Double> {
        Binding(get: { if case let .number(n)? = self.settings.value(forKey: key) { n } else { 0 } },
                set: { self.set(key, .number($0)) })
    }

    func text(_ key: String) -> Binding<String> {
        Binding(get: { if case let .text(s)? = self.settings.value(forKey: key) { s } else { "" } },
                set: { self.set(key, .text($0)) })
    }
}

// MARK: - The window

/// One Settings window laid out like System Settings: a translucent sidebar
/// of panes, each a grouped form; the title is the pane's name.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate, NSToolbarDelegate {
    static let width: CGFloat = 715
    static let sidebarWidth: CGFloat = 215

    let model: SettingsModel
    let window: NSWindow
    private var title: AnyCancellable?
    private var placed = false // where it was last time, or centered on the first show

    init(model: SettingsModel) {
        self.model = model
        // AppKit's split view: its sidebar item is the real translucent sidebar, full height under the title bar.
        let split = NSSplitViewController()
        let sidebar = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: SettingsSidebar().environmentObject(model)))
        sidebar.canCollapse = false
        sidebar.minimumThickness = Self.sidebarWidth
        sidebar.maximumThickness = Self.sidebarWidth
        split.addSplitViewItem(sidebar)
        let detail = NSSplitViewItem(viewController: NSHostingController(rootView: SettingsDetail().environmentObject(model)))
        detail.titlebarSeparatorStyle = .automatic
        split.addSplitViewItem(detail)
        window = NSWindow(contentViewController: split)
        super.init()
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        let toolbar = NSToolbar(identifier: "settings")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = true // the title sits on the pane's own background, as in System Settings
        window.setContentSize(NSSize(width: Self.width, height: 640))
        window.contentMinSize = NSSize(width: Self.width, height: 440)
        window.contentMaxSize = NSSize(width: Self.width, height: 4000)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
        window.isReleasedWhenClosed = false
        window.delegate = self
        placed = model.remembersPane && window.setFrameUsingName("Settings")
        if model.remembersPane { window.setFrameAutosaveName("Settings") }
        title = model.$pane.sink { [weak window] in window?.title = $0.title }
    }

    func show(_ pane: SettingsPane? = nil) {
        if let pane { model.pane = pane }
        model.reload()
        model.watch(true)
        model.cliStatus = CLITool.status()
        if !placed {
            window.center()
            placed = true
        }
        NSApp.mainMenu = SettingsWindow.mainMenu // ⌘W, ⌘Q and editing keys while it is open
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // The title sits over the detail pane, after the sidebar's edge.
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.sidebarTrackingSeparator] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.sidebarTrackingSeparator] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? { nil }

    func windowDidBecomeKey(_ notification: Notification) { model.reload() }
    func windowDidResignKey(_ notification: Notification) { model.recording = nil }

    func windowWillClose(_ notification: Notification) {
        model.recording = nil
        model.conflict = nil
        model.flush()
        model.watch(false)
        model.madePreview?.release()
        NSApp.mainMenu = nil
    }

    /// A small main menu: an accessory app has none, so text fields would not copy or paste.
    static let mainMenu: NSMenu = {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = NSMenu(title: title)
            items.forEach(item.submenu!.addItem)
            main.addItem(item)
        }
        submenu("mielwm", [NSMenuItem(title: "Quit mielwm", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")])
        submenu("Edit", [
            NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"),
            NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ])
        submenu("Window", [NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")])
        return main
    }()
}

struct SettingsSidebar: View {
    @EnvironmentObject var model: SettingsModel

    var body: some View {
        List(SettingsPane.allCases, id: \.self, selection: Binding(get: { model.pane }, set: { if let p = $0 { model.pane = p } })) { pane in
            Label { Text(pane.title) } icon: { PaneIcon(pane: pane) }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }
}

struct SettingsDetail: View {
    @EnvironmentObject var model: SettingsModel

    var body: some View {
        Group {
            switch model.pane {
            case .general: GeneralPane()
            case .layout: LayoutPane()
            case .keyboard: KeyboardPane()
            case .appearance: AppearancePane()
            case .advanced: AdvancedPane()
            }
        }
        .formStyle(.grouped)
        // The title bar is clear: scrolled rows stop at its edge, under a hairline as in System Settings.
        .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y + $0.contentInsets.top > 1 }) { model.scrolled = $1 }
        .clipped()
        .overlay(alignment: .top) { if model.scrolled { Divider() } }
        .alert("Can't save the settings", isPresented: Binding(get: { model.problem != nil }, set: { if !$0 { model.problem = nil } })) {
            Button("OK") { model.problem = nil }
        } message: {
            Text(model.problem ?? "")
        }
    }
}

struct PaneIcon: View {
    let pane: SettingsPane

    var body: some View {
        Image(systemName: pane.symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(pane.color.gradient))
            .accessibilityHidden(true)
    }
}

// MARK: - General

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

// MARK: - Layout & workspaces

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
                GapDiagram(settings: s).frame(height: 132).frame(maxWidth: .infinity).padding(.vertical, 4)
                GapField(title: "Between windows, side by side", key: "gaps:inner_horizontal")
                GapField(title: "Between windows, above each other", key: "gaps:inner_vertical")
                GapField(title: "Left edge", key: "gaps:outer_left")
                GapField(title: "Right edge", key: "gaps:outer_right")
                GapField(title: "Bottom edge", key: "gaps:outer_bottom")
                GapField(title: "Top edge, built-in display", key: "gaps:outer_top")
                GapField(title: "Top edge, other displays", key: "gaps:outer_top_external")
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

    var body: some View {
        Canvas { context, size in
            let w = min(size.width, (size.height - 8) * 1.6)
            let screen = CGRect(x: (size.width - w) / 2, y: 4, width: w, height: size.height - 8)
            let k = 0.5 // half size, so the gaps read at a glance
            context.fill(Path(roundedRect: screen, cornerRadius: 7), with: .color(.secondary.opacity(0.1)))
            context.stroke(Path(roundedRect: screen.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 7), with: .color(.secondary.opacity(0.35)), lineWidth: 1)
            let s = settings
            let area = CGRect(x: screen.minX + s.gapOuterLeft * k, y: screen.minY + s.gapOuterTop * k,
                              width: screen.width - (s.gapOuterLeft + s.gapOuterRight) * k,
                              height: screen.height - (s.gapOuterTop + s.gapOuterBottom) * k)
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
        .accessibilityLabel("A display with three windows and the gaps around them")
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

// MARK: - Appearance

struct AppearancePane: View {
    @EnvironmentObject var model: SettingsModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let look = model.settings.look
        Form {
            Section {
                AppearancePreviewView(settings: model.settings, dark: colorScheme == .dark, preview: model.preview)
                AccentPicker()
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

// MARK: - Advanced

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
                    case let .installed(at): Text("Installed as \(at). Try “\(CLITool.name) overview”.")
                    case let .taken(at): Text("\(at) is another file. Install replaces it.")
                    case .missing: Text("Links “\(CLITool.name)” into ~/.local/bin, to drive mielwm from Terminal.")
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

/// The `mielwm` binary linked into ~/.local/bin.
enum CLITool {
    enum Status: Equatable { case missing, installed(String), taken(String) }

    static var name: String { Bundle.main.executableURL?.lastPathComponent ?? "mielwm" }
    static func link(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".local/bin").appendingPathComponent(name)
    }

    static var target: URL? { Bundle.main.executableURL?.resolvingSymlinksInPath() }

    static func status(link: URL = link()) -> Status {
        let shown = (link.path as NSString).abbreviatingWithTildeInPath
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else {
            return FileManager.default.fileExists(atPath: link.path) ? .taken(shown) : .missing
        }
        return URL(fileURLWithPath: dest).resolvingSymlinksInPath() == target ? .installed(shown) : .taken(shown)
    }

    static func install(link: URL = link()) throws -> Status {
        guard let target else { return .missing }
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil || FileManager.default.fileExists(atPath: link.path) {
            try FileManager.default.removeItem(at: link)
        }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        return status(link: link)
    }

    static func remove(link: URL = link()) -> Status {
        if case .installed = status(link: link) { try? FileManager.default.removeItem(at: link) }
        return status(link: link)
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

var appVersion: String {
    let info = Bundle.main.infoDictionary
    guard let version = info?["CFBundleShortVersionString"] as? String else { return "Development build" }
    return (info?["CFBundleVersion"] as? String).map { "\(version) (\($0))" } ?? version
}

// MARK: - Small views

/// A slider with its value; changes apply as it moves and are saved when it is let go.
struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String
    @EnvironmentObject var model: SettingsModel

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, format: @escaping (Double) -> String) {
        self.title = title
        _value = value
        self.range = range
        self.format = format
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Slider(value: $value, in: range) { Text(title) } onEditingChanged: { if !$0 { model.flush() } }
                    .labelsHidden()
                    .controlSize(.small)
                Text(format(value)).monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
            }
            .frame(width: 220)
        }
    }
}

extension Text {
    func settingsFooter() -> some View {
        font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// macOS's own three-finger swipe between full-screen apps (Trackpad > More Gestures), built in or Magic Trackpad.
func systemThreeFingerSwipe() -> Bool {
    ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"].contains { domain in
        CFPreferencesAppSynchronize(domain as CFString)
        return (CFPreferencesCopyAppValue("TrackpadThreeFingerHorizSwipeGesture" as CFString, domain as CFString) as? Int) == 2
    }
}
