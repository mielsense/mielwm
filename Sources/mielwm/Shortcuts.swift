import MielCore

/// What a recorder sets: one action's shortcut, or a whole family's modifiers.
enum ShortcutTarget: Hashable {
    case action(Action), family(ShortcutFamily)
}

/// One recorder: an action and the chord it shows (nil: an empty recorder that adds one).
struct ShortcutSlot: Hashable {
    var target: ShortcutTarget
    var chord: KeyChord?
}

/// Recorded keys that other actions already have, waiting for "Use here" or "Cancel".
struct ShortcutConflict: Equatable {
    var slot: ShortcutSlot
    var changes: [String: SettingValue?]
    var chords: [KeyChord]
    var others: [Action]
}

/// A row of the Keyboard pane: an action, or a family edited as one shortcut.
struct ShortcutItem {
    var target: ShortcutTarget
    var name: String
    var detail: String?
}

/// The shortcuts that make sense anywhere, grouped, in plain words. Other
/// actions still work from config.json and the command line.
let shortcutGroups: [(title: String, items: [ShortcutItem])] = [
    ("Overview", [
        ShortcutItem(target: .action(.toggleOverview), name: "Overview", detail: "Zoom out to every window, and back."),
    ]),
    ("Windows", [
        ShortcutItem(target: .action(.switchWindow(forward: true)), name: "Recent windows",
                     detail: "Tap to go back to the last window, hold for the list. In a stack, the next window."),
        ShortcutItem(target: .action(.switchWindow(forward: false)), name: "Recent windows, backwards"),
        ShortcutItem(target: .action(.fill), name: "Fill the screen", detail: "Again puts the window back."),
        ShortcutItem(target: .action(.fullscreen), name: "Fullscreen"),
        ShortcutItem(target: .action(.pin), name: "Pin to the screen", detail: "The window stays put while the canvas moves."),
        ShortcutItem(target: .action(.grow), name: "Grow"),
        ShortcutItem(target: .action(.shrink), name: "Shrink"),
    ]),
    ("Layout", [
        ShortcutItem(target: .action(.layoutTiles), name: "Tiles", detail: "Again turns side by side into above each other."),
        ShortcutItem(target: .action(.layoutStack), name: "Stack"),
        ShortcutItem(target: .action(.toggleFloating), name: "Float or tile"),
        ShortcutItem(target: .action(.arrange), name: "Tidy windows", detail: "Lines up the floating windows on the canvas, grouped by app."),
    ]),
    ("Workspaces", [
        ShortcutItem(target: .family(.workspace), name: "Go to workspace"),
        ShortcutItem(target: .family(.moveToWorkspace), name: "Move window to workspace", detail: "And go there with it."),
        ShortcutItem(target: .action(.workspaceStep(forward: true)), name: "Next workspace"),
        ShortcutItem(target: .action(.workspaceStep(forward: false)), name: "Previous workspace"),
        ShortcutItem(target: .action(.workspaceBackAndForth), name: "Last workspace", detail: "The one you were on before. Again goes back."),
    ]),
    ("Focus & move", [
        ShortcutItem(target: .family(.focus), name: "Focus", detail: "The nearest window in that direction."),
        ShortcutItem(target: .family(.nudge), name: "Move window", detail: "Swaps tiles, or nudges a floating window."),
    ]),
    ("mielwm", [
        ShortcutItem(target: .action(.settings), name: "Settings"),
    ]),
]

/// Keys of the zoomed-out canvas: not shortcuts, listed so they are known.
let overviewKeys: [(keys: String, name: String)] = [
    ("↩", "Go to the selected window"), ("⇧↩", "Bring it here"), ("⌘1–9", "Go to that search result"),
    ("⌘0", "Fit every window"), ("⌘F", "Frame the selected window"), ("⌘A", "Tidy windows"),
    ("⌘Z  ⌘⇧Z", "Undo, redo"), ("⌘,", "Appearance settings"), ("⎋", "Clear the search, then go back"),
]

/// An action in plain words, for conflicts and the actions only config.json binds.
func actionName(_ action: Action) -> String {
    for group in shortcutGroups {
        for item in group.items {
            if item.target == .action(action) { return item.name }
            if case let .family(f) = item.target, f.contains(action) { return "\(item.name) (\(memberName(action)))" }
        }
    }
    switch action {
    case .search: return "Search windows"
    case .tune: return "Appearance settings"
    case .help: return "Every key"
    case .fit: return "Fit every window"
    case .frame: return "Frame the window"
    case .zoomIn: return "Zoom in"
    case .zoomOut: return "Zoom out"
    case let .pan(d): return "Pan \(d.rawValue)"
    case .undo: return "Undo"
    case .redo: return "Redo"
    case .summon: return "Bring the selected window here"
    case .land: return "Go to the selected window"
    case .back: return "Go back"
    case .refresh: return "Refresh the window list"
    default: return action.command
    }
}

/// A family member by its key: "3", "Left".
func memberName(_ action: Action) -> String {
    switch action {
    case let .workspace(n), let .moveToWorkspace(n): "\(n)"
    case let .focus(d), let .nudge(d): d.rawValue.capitalized
    default: action.command
    }
}

/// What macOS itself does with a chord, for a note under the row.
func systemUse(_ chord: KeyChord) -> String? {
    switch chord.description {
    case "ctrl+space", "ctrl+opt+space": "macOS also switches input sources with \(chord.symbol)."
    case "shift+cmd+3", "shift+cmd+4", "shift+cmd+5": "macOS also takes screenshots with \(chord.symbol)."
    case "ctrl+left", "ctrl+right": "Mission Control also switches Spaces with \(chord.symbol)."
    case "ctrl+up": "Mission Control also opens with \(chord.symbol)."
    case "ctrl+down": "App Exposé also opens with \(chord.symbol)."
    case "cmd+grave": "macOS also cycles an app's windows with \(chord.symbol)."
    case "ctrl+cmd+space": "macOS also opens Emoji & Symbols with \(chord.symbol)."
    case "ctrl+cmd+q": "macOS also locks the screen with \(chord.symbol)."
    case "opt+cmd+escape": "macOS also opens Force Quit with \(chord.symbol)."
    case "opt+cmd+d": "macOS also hides the Dock with \(chord.symbol)."
    case "ctrl+cmd+f": "Apps also enter full screen with \(chord.symbol)."
    default: nil
    }
}
