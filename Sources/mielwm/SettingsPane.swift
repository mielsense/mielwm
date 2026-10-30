import SwiftUI

/// The Settings window's panes, in sidebar order; actions can open it at one.
/// The raw values are stored as the last pane, so older ones stay.
enum SettingsPane: String, CaseIterable {
    case general, layout, windows, overview, keyboard, trackpad, appearance, menubar, integrations, advanced, about

    var title: String {
        switch self {
        case .general: "General"
        case .layout: "Layout"
        case .windows: "Windows"
        case .overview: "Overview"
        case .keyboard: "Keyboard"
        case .trackpad: "Trackpad & mouse"
        case .appearance: "Appearance"
        case .menubar: "Menu bar"
        case .integrations: "AeroSpace & Barik"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    /// The line under the pane's name in its header card.
    var summary: String {
        switch self {
        case .general: "Start mielwm when you log in, and choose how it remembers and animates your windows."
        case .layout: "How new windows tile, and the gaps around them and the screen edges."
        case .windows: "Apps whose windows float above the tiles, and apps that always open on one workspace."
        case .overview: "How far the canvas zooms out, the lens at its edges, and what shows on it."
        case .keyboard: "Click a shortcut, then type the new keys. Esc cancels, Delete clears it."
        case .trackpad: "Swipes, the pointer in the overview, and the keys you hold to drag a window."
        case .appearance: "The overview's accent color, background, grid and windows."
        case .menubar: "What the mielwm item in the menu bar shows."
        case .integrations: "Show your workspaces in Barik, or bring your AeroSpace settings over."
        case .advanced: "The config file, the command-line tool and a fresh start."
        case .about: "Your windows on one endless canvas, tiled in workspaces."
        }
    }

    /// The sidebar's groups, spaced apart like System Settings'.
    static let groups: [[SettingsPane]] = [[.general], [.layout, .windows, .overview], [.keyboard, .trackpad], [.appearance, .menubar], [.integrations, .advanced, .about]]

    /// What search finds the pane by, besides its name: every row title in it, then other words for them.
    /// Keep these in step with the pane's rows.
    var keywords: [String] {
        switch self {
        case .general: ["Open at login", "Remember where windows are", "Animation", "Animate the camera", "Speed", "Startup", "Restart"]
        case .layout: ["Layout", "Tiles", "Stack", "Floating", "Orientation", "Automatic", "Side by side", "Above each other", "Gaps",
                       "Between windows, side by side", "Between windows, above each other", "Left edge", "Right edge", "Bottom edge",
                       "Top edge", "Top gap", "Status bar", "New windows"]
        case .windows: ["Floating apps", "Workspace rules", "Add app", "Apps"]
        case .overview: ["Zoomed-out level", "Show window names", "Show the minimap", "Lens", "Bend the edges", "Strength", "Magnification", "Zoom"]
        case .keyboard: ["Shortcuts", "Keys", "Hotkeys", "Restore all shortcuts", "In the overview"]
        case .trackpad: ["Swipe between workspaces", "Three fingers", "Move and resize windows", "Use the pointer in the overview",
                         "Panning speed", "Zoom speed", "Pointer and scrolling", "Mouse", "Drag", "Modifier", "Scroll wheel", "Middle button"]
        case .appearance: ["Accent color", "Show the desktop picture", "Wallpaper", "Dim", "Blur", "Blur amount", "Show the grid", "Grid style",
                           "Dots", "Lines", "Opacity", "Corner rounding", "Shadows", "Preview"]
        case .menubar: ["Menu bar item", "All workspaces", "Current only", "Icon", "Workspace numbers"]
        case .integrations: ["Work with Barik", "Import from AeroSpace", "Barik", "AeroSpace"]
        case .advanced: ["Config file", "config.json", "Command-line tool", "Terminal", "Reset all settings"]
        case .about: ["Version", "Website", "Documentation", "Changelog", "Source code", "GitHub", "License"]
        }
    }

    /// The setting a search for `query` matches in this pane: nil when it matches only the name, or nothing.
    func match(_ query: String) -> (matches: Bool, keyword: String?) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return (true, nil) }
        if title.localizedStandardContains(q) { return (true, nil) }
        let keyword = keywords.first { $0.localizedStandardContains(q) }
        return (keyword != nil, keyword)
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .layout: "square.split.2x1.fill"
        case .windows: "macwindow.on.rectangle"
        case .overview: "square.grid.2x2.fill" // the status menu's Overview item uses it too
        case .keyboard: "keyboard.fill"
        case .trackpad: "hand.point.up.left.fill"
        case .appearance: "circle.lefthalf.filled"
        case .menubar: "menubar.rectangle"
        case .integrations: "puzzlepiece.extension.fill"
        case .advanced: "wrench.and.screwdriver.fill"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general, .keyboard, .trackpad, .advanced: Design.Tint.gray
        case .layout: Design.Tint.blue
        case .windows: Design.Tint.indigo
        case .overview: Design.Tint.cyan
        case .appearance: Design.Tint.graphite
        case .menubar: Design.Tint.blue
        case .integrations: Design.Tint.green
        case .about: Design.Tint.gray
        }
    }

    /// Its icon; About shows the app's own.
    @MainActor func icon(size: CGFloat) -> IconTile {
        self == .about ? IconTile(image: appIcon(), size: size) : IconTile(symbol, tint: tint, size: size)
    }
}
