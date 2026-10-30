import AppKit
import Combine
import MielCore
import SwiftUI

/// One Settings window laid out like System Settings: a translucent sidebar
/// of panes, each a grouped form; the title is the pane's name.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate, NSToolbarDelegate {
    static let width: CGFloat = 715
    static let sidebarWidth: CGFloat = 215

    let model: SettingsModel
    let window: NSWindow
    private var title: AnyCancellable?
    private var titleShown: AnyCancellable?
    private var placed = false // where it was last time, or centered on the first show

    init(model: SettingsModel) {
        self.model = model
        // AppKit's split view: its sidebar item is the real translucent sidebar, full height under the title bar.
        let split = NSSplitViewController()
        // macOS 26 floats the sidebar as glass with no divider of its own.
        if #unavailable(macOS 26) {
            split.splitView = SeamlessSplitView()
            split.splitView.isVertical = true
        }
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
        // As in System Settings, the name shows in the title bar once the header card that has it scrolls away.
        titleShown = model.$pastHeader.sink { [weak window] in window?.titleVisibility = $0 ? .visible : .hidden }
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
        model.readScreen(window.screen)
    }

    // The title sits over the detail pane, after the sidebar's edge.
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.sidebarTrackingSeparator] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.sidebarTrackingSeparator] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? { nil }

    func windowDidBecomeKey(_ notification: Notification) {
        model.reload()
        model.readScreen(window.screen) // a status bar may have come or gone meanwhile
    }

    func windowDidChangeScreen(_ notification: Notification) { model.readScreen(window.screen) }
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

/// Before macOS 26, no divider: the sidebar's translucency already sets it apart, as in System Settings.
final class SeamlessSplitView: NSSplitView {
    override func layout() {
        super.layout()
        // The sidebar's divider is its own (vibrant) view, beside the panes.
        for v in subviews where !arrangedSubviews.contains(v) && String(describing: type(of: v)).contains("Divider") { v.isHidden = true }
    }
}

struct SettingsSidebar: View {
    @EnvironmentObject var model: SettingsModel

    var body: some View {
        let query = model.paneQuery
        // Each group's panes the search finds, with the setting it found in them.
        let groups = SettingsPane.groups.map { $0.compactMap { pane in
            let m = pane.match(query)
            return m.matches ? (pane: pane, keyword: m.keyword) : nil
        } }
        VStack(spacing: 0) {
            SearchField(text: $model.paneQuery)
                .accessibilityLabel("Search settings")
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 4)
            List(selection: Binding(get: { model.pane }, set: { if let p = $0 { model.pane = p } })) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, found in
                    if !found.isEmpty {
                        Section {
                            ForEach(found, id: \.pane) { pane, keyword in
                                Label {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(pane.title)
                                        if let keyword {
                                            Text(keyword).font(Design.secondary).foregroundStyle(.secondary)
                                        }
                                    }
                                } icon: {
                                    pane.icon(size: Design.Tile.sidebar)
                                }
                                .tag(pane)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .overlay {
                if groups.allSatisfy(\.isEmpty) {
                    Text("No Results").font(Design.row).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct SettingsDetail: View {
    @EnvironmentObject var model: SettingsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            pane
                .id(model.pane)
                .transition(.opacity)
        }
        .animation(Design.paneChange(reduceMotion: reduceMotion), value: model.pane)
        .formStyle(.grouped)
        .onScrollGeometryChange(for: Int.self, of: { g in
            let y = g.contentOffset.y + g.contentInsets.top
            return y > 120 ? 2 : y > 1 ? 1 : 0
        }) { _, at in
            if model.scrolled != (at > 0) { model.scrolled = at > 0 }
            if model.pastHeader != (at > 1) { model.pastHeader = at > 1 }
        }
        .modifier(TitlebarEdge(scrolled: model.scrolled))
        .alert("Can't save the settings", isPresented: Binding(get: { model.problem != nil }, set: { if !$0 { model.problem = nil } })) {
            Button("OK") { model.problem = nil }
        } message: {
            Text(model.problem ?? "")
        }
    }

    @ViewBuilder private var pane: some View {
        switch model.pane {
        case .general: GeneralPane()
        case .layout: LayoutPane()
        case .windows: WindowsPane()
        case .overview: OverviewPane()
        case .keyboard: KeyboardPane()
        case .trackpad: TrackpadPane()
        case .appearance: AppearancePane()
        case .menubar: MenuBarPane()
        case .integrations: IntegrationsPane()
        case .advanced: AdvancedPane()
        case .about: AboutPane()
        }
    }
}

/// Where scrolled rows meet the title bar. macOS 26 fades them under its glass
/// by itself; before, they stop at its edge under a hairline, as System Settings does there.
private struct TitlebarEdge: ViewModifier {
    let scrolled: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
        } else {
            content
                .clipped()
                .overlay(alignment: .top) { if scrolled { Divider() } }
        }
    }
}
