import AppKit
import MielCore
import SwiftUI

struct MenuBarPane: View {
    @EnvironmentObject var model: SettingsModel

    var body: some View {
        Form {
            Section { PaneHeader(pane: .menubar) }
            Section {
                VisualPicker(title: "Menu bar item", subtitle: note, selection: Binding(get: { model.settings.menuBarStyle }, set: { model.apply($0.configChanges) }),
                             options: MenuBarStyle.allCases, name: \.title, size: CGSize(width: 92, height: 40)) { MenuBarThumbnail(style: $0) }
            } footer: {
                Text("While the config file has errors, a warning sign shows instead. The menu lists your workspaces either way.").settingsFooter()
            }
            Section("On screen") {
                Toggle(isOn: model.flag("notices:workspace")) {
                    Text("Show workspace on switch")
                    Text("The same numbers appear at the bottom of the display for a moment when you switch.")
                }
            }
        }
    }

    private var note: String {
        if model.settings.barik, model.settings.menuBarStyle != .icon {
            return "Barik shows your workspaces too. Icon keeps them from showing twice."
        }
        switch model.settings.menuBarStyle {
        case .all: return "The numbers of the workspaces that have windows, with the current one filled."
        case .current: return "Only the current workspace's number, for a crowded menu bar."
        case .icon: return "The mielwm icon. Its menu lists the workspaces."
        }
    }
}

extension MenuBarStyle {
    var title: String {
        switch self {
        case .all: "All workspaces"
        case .current: "Current only"
        case .icon: "Icon"
        }
    }

    /// The config edits that set this style. They drop the older menubar:workspaces switch, which would say the same thing.
    var configChanges: [String: SettingValue?] {
        ["menubar:style": MielCore.Settings.entry("menubar:style", .text(rawValue)), "menubar:workspaces": nil]
    }
}

/// The right end of a menu bar with mielwm's item as `style` draws it, beside the clock.
struct MenuBarThumbnail: View {
    let style: MenuBarStyle

    var body: some View {
        let image: NSImage? = switch style {
        case .all: workspaceIndicator([1, 2, 3], current: 2)
        case .current: workspaceIndicator([2], current: 2)
        case .icon: menuBarIconImage
        }
        MiniDesktop(menuBar: 0) {
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                if let image { Image(nsImage: image).renderingMode(.template).resizable().scaledToFit().frame(height: 9) }
                Image(systemName: "wifi").font(.system(size: 7, weight: .semibold))
                Text("9:41").font(.system(size: 7.5, weight: .medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .frame(height: 15)
            .background(.white.opacity(0.4))
        }
    }
}
