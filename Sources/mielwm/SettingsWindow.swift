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
