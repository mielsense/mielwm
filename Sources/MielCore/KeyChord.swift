import Foundation

/// A key with modifiers, written "ctrl+opt+g" in the config.
public struct KeyChord: Hashable, Codable, Sendable, CustomStringConvertible {
    public var modifiers: Modifiers
    /// Lowercase key name: a...z, 0...9, f1...f12, tab, space, return, escape,
    /// delete, forwarddelete, left, right, up, down, minus, equal, comma,
    /// period, slash, semicolon, quote, grave, backslash, leftbracket,
    /// rightbracket, home, end, pageup, pagedown.
    public var key: String

    public init(modifiers: Modifiers, key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    static let keyNames: Set<String> = {
        var names: Set<String> = ["tab", "space", "return", "escape", "delete", "forwarddelete", "left", "right", "up", "down",
                                  "minus", "equal", "comma", "period", "slash", "semicolon", "quote", "grave", "backslash",
                                  "leftbracket", "rightbracket", "home", "end", "pageup", "pagedown"]
        names.formUnion("abcdefghijklmnopqrstuvwxyz0123456789".map(String.init))
        names.formUnion((1 ... 12).map { "f\($0)" })
        return names
    }()

    static let aliases: [String: String] = [
        "-": "minus", "=": "equal", ",": "comma", ".": "period", "/": "slash", ";": "semicolon", "'": "quote",
        "`": "grave", "\\": "backslash", "[": "leftbracket", "]": "rightbracket", "esc": "escape", "enter": "return",
        "backspace": "delete", "←": "left", "→": "right", "↑": "up", "↓": "down",
    ]

    /// "opt", "option", "alt", "⌥"; "ctrl", "control", "⌃"; "cmd", "command", "⌘"; "shift", "⇧".
    static func modifier(_ word: String) -> Modifiers? {
        switch word {
        case "opt", "option", "alt", "⌥": .option
        case "ctrl", "control", "⌃": .control
        case "cmd", "command", "⌘": .command
        case "shift", "⇧": .shift
        default: nil
        }
    }

    /// "ctrl+opt" as modifiers, nil if any word is not one.
    public static func modifiers(_ text: String) -> Modifiers? {
        var m: Modifiers = []
        for word in text.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            guard let one = modifier(word) else { return nil }
            m.insert(one)
        }
        return m.isEmpty ? nil : m
    }

    public init?(_ text: String) {
        var parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.popLast(), !last.isEmpty else { return nil }
        var m: Modifiers = []
        for word in parts {
            guard let one = Self.modifier(word) else { return nil }
            m.insert(one)
        }
        let key = Self.aliases[last] ?? last
        guard Self.keyNames.contains(key) else { return nil }
        self.init(modifiers: m, key: key)
    }

    public var description: String {
        let names: [(Modifiers, String)] = [(.control, "ctrl"), (.option, "opt"), (.shift, "shift"), (.command, "cmd")]
        return (names.filter { modifiers.contains($0.0) }.map(\.1) + [key]).joined(separator: "+")
    }

    /// "⌃⌥G", as the help sheet shows it.
    public var symbol: String {
        let names: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let keySymbols = ["left": "←", "right": "→", "up": "↑", "down": "↓", "tab": "⇥", "return": "↩", "escape": "⎋",
                          "delete": "⌫", "minus": "-", "equal": "=", "comma": ",", "period": ".", "slash": "/",
                          "semicolon": ";", "space": "Space"]
        return names.filter { modifiers.contains($0.0) }.map(\.1).joined() + (keySymbols[key] ?? key.uppercased())
    }
}

public extension Action {
    /// `mielwm <command>` and binding names: "overview", "search [text]",
    /// "tune", "help", "switch next|prev", "focus|nudge|pan left|right|up|down",
    /// "zoom in|out", "fit", "frame", "summon", "land", "back", "fill",
    /// "fullscreen", "pin", "grow", "shrink", "arrange", "undo", "redo",
    /// "refresh", "noop", "workspace-back-and-forth".
    init?(command: String) {
        let words = command.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1).map(String.init)
        guard let verb = words.first?.lowercased() else { return nil }
        let rest = words.count > 1 ? words[1].trimmingCharacters(in: .whitespaces) : ""
        let direction = Direction(rawValue: rest.lowercased())
        switch (verb, rest.lowercased()) {
        case ("overview", ""): self = .toggleOverview
        case ("search", _): self = .search(rest.isEmpty ? nil : rest)
        case ("tune", ""): self = .tune
        case ("help", ""): self = .help
        case ("switch", "next"): self = .switchWindow(forward: true)
        case ("switch", "prev"): self = .switchWindow(forward: false)
        case ("focus", _) where direction != nil: self = .focus(direction!)
        case ("nudge", _) where direction != nil: self = .nudge(direction!)
        case ("pan", _) where direction != nil: self = .pan(direction!)
        case ("zoom", "in"): self = .zoomIn
        case ("zoom", "out"): self = .zoomOut
        case ("fit", ""): self = .fit
        case ("frame", ""): self = .frame
        case ("summon", ""): self = .summon
        case ("land", ""): self = .land
        case ("back", ""): self = .back
        case ("fill", ""): self = .fill
        case ("fullscreen", ""): self = .fullscreen
        case ("pin", ""): self = .pin
        case ("grow", ""): self = .grow
        case ("shrink", ""): self = .shrink
        case ("arrange", ""): self = .arrange
        case ("undo", ""): self = .undo
        case ("redo", ""): self = .redo
        case ("refresh", ""): self = .refresh
        case ("noop", ""): self = .noop
        case ("layout", "tiles"), ("layout", "tiling"): self = .layoutTiles
        case ("layout", "stack"), ("layout", "accordion"): self = .layoutStack
        case ("layout", "floating"): self = .toggleFloating
        case ("workspace", "next"): self = .workspaceStep(forward: true)
        case ("workspace", "prev"): self = .workspaceStep(forward: false)
        case ("workspace-back-and-forth", ""): self = .workspaceBackAndForth
        case ("workspace", _) where Int(rest).map({ (1 ... 9).contains($0) }) == true: self = .workspace(Int(rest)!)
        case ("move-to-workspace", _), ("move-node-to-workspace", _):
            guard let n = Int(rest), (1 ... 9).contains(n) else { return nil }
            self = .moveToWorkspace(n)
        case ("settings", ""): self = .settings
        default: return nil
        }
    }

    var command: String {
        switch self {
        case .toggleOverview: "overview"
        case let .search(text): text.map { "search \($0)" } ?? "search"
        case .tune: "tune"
        case .help: "help"
        case let .switchWindow(forward): forward ? "switch next" : "switch prev"
        case let .focus(d): "focus \(d.rawValue)"
        case let .nudge(d): "nudge \(d.rawValue)"
        case let .pan(d): "pan \(d.rawValue)"
        case .zoomIn: "zoom in"
        case .zoomOut: "zoom out"
        case .fit: "fit"
        case .frame: "frame"
        case .summon: "summon"
        case .land: "land"
        case .back: "back"
        case .fill: "fill"
        case .fullscreen: "fullscreen"
        case .pin: "pin"
        case .grow: "grow"
        case .shrink: "shrink"
        case .arrange: "arrange"
        case .undo: "undo"
        case .redo: "redo"
        case .refresh: "refresh"
        case .noop: "noop"
        case .layoutTiles: "layout tiles"
        case .layoutStack: "layout stack"
        case .toggleFloating: "layout floating"
        case let .workspace(n): "workspace \(n)"
        case let .workspaceStep(forward): forward ? "workspace next" : "workspace prev"
        case .workspaceBackAndForth: "workspace-back-and-forth"
        case let .moveToWorkspace(n): "move-to-workspace \(n)"
        case .settings: "settings"
        }
    }
}
