import SwiftUI

/// The Settings window's panes; actions can open it at one.
enum SettingsPane: String, CaseIterable {
    case general, layout, keyboard, appearance, advanced

    var title: String {
        switch self {
        case .general: "General"
        case .layout: "Layout & workspaces"
        case .keyboard: "Keyboard"
        case .appearance: "Appearance"
        case .advanced: "Advanced"
        }
    }

    /// The sidebar icon: a white symbol on a colored rounded square, as System Settings draws them.
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .layout: "rectangle.split.2x1.fill"
        case .keyboard: "keyboard.fill"
        case .appearance: "paintpalette.fill"
        case .advanced: "slider.horizontal.3"
        }
    }

    var color: Color {
        switch self {
        case .general, .keyboard: Color(nsColor: .systemGray)
        case .layout: Color(nsColor: .systemBlue)
        case .appearance: Color(nsColor: .systemPurple)
        case .advanced: Color(nsColor: .darkGray)
        }
    }
}
