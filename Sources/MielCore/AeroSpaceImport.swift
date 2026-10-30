import Foundation

/// What mielwm can take over from an AeroSpace config: gaps, the default
/// layout and orientation, per-app workspace and floating rules, rules by
/// app name or title, and the main-mode keys whose commands mielwm has.
public struct AeroSpaceImport: Hashable, Sendable {
    public var gaps: [String: Double] = [:] // gaps:* keys
    public var layout: LayoutMode?
    public var orientation: TileOrientation?
    public var workspaceRules: [String: Int] = [:] // bundle id → workspace
    public var floatingApps: [String] = []
    public var windowRules: [String: WindowRule] = [:] // by app name or title, named by their block
    public var autoBackAndForth = false // a workspace key used --auto-back-and-forth
    public var bindings: [String: String] = [:] // mielwm chord → command

    public var isEmpty: Bool { self == AeroSpaceImport() }

    /// ~/.config/aerospace/aerospace.toml, or ~/.aerospace.toml; nil if neither exists.
    public static func standardURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        [".config/aerospace/aerospace.toml", ".aerospace.toml"].map { home.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    public init() {}

    /// Reads the forms above; everything else, and anything it can't read, is skipped.
    public init(toml text: String) {
        var floating: [String] = []
        struct Block { var app, name, title: String?, run: [String] = [] } // one [[on-window-detected]]
        var blocks: [Int: Block] = [:]
        for entry in parseTOML(text) {
            let path = entry.section.isEmpty ? entry.key : entry.section + "." + entry.key
            if path.hasPrefix("gaps."), let name = Self.gapNames[String(path.dropFirst(5))] {
                let (builtIn, other) = gapValues(entry.value)
                if name == "outer_top" {
                    if let v = builtIn ?? other { gaps["gaps:outer_top"] = v }
                    if let v = other ?? builtIn { gaps["gaps:outer_top_external"] = v }
                } else if let v = other ?? builtIn {
                    gaps["gaps:" + name] = v
                }
            } else if path == "default-root-container-layout", case let .string(s) = entry.value {
                layout = s == "accordion" ? .stack : s == "tiles" ? .tiles : nil
            } else if path == "default-root-container-orientation", case let .string(s) = entry.value {
                orientation = TileOrientation(rawValue: s)
            } else if entry.section == "on-window-detected" {
                let text = entry.value.strings.first
                switch entry.key {
                case "if.app-id": blocks[entry.block, default: Block()].app = text
                case "if.app-name-regex-substring": blocks[entry.block, default: Block()].name = text
                case "if.window-title-regex-substring": blocks[entry.block, default: Block()].title = text
                case "run": blocks[entry.block, default: Block()].run = entry.value.strings
                default: break
                }
            } else if entry.section == "mode.main.binding", let chord = aeroSpaceChord(entry.key),
                      let first = entry.value.strings.first, let command = aeroSpaceCommand(first),
                      Settings.defaultBindings[chord.description]?.hasPrefix("switch ") != true { // ⌥Tab stays the window switcher
                bindings[chord.description] = command
                if first.split(separator: " ").contains("--auto-back-and-forth") { autoBackAndForth = true }
            }
        }
        for (number, rule) in blocks.sorted(by: { $0.key < $1.key }).map(\.value).enumerated() {
            var workspace: Int?, floats = false
            for command in rule.run {
                let words = command.split(separator: " ")
                if words.first == "move-node-to-workspace", let n = words.last.flatMap({ Int($0) }), (1 ... 9).contains(n) {
                    workspace = n
                } else if words.starts(with: ["layout", "floating"]) {
                    floats = true
                }
            }
            if rule.name != nil || rule.title != nil { // by name or title: a window rule
                guard workspace != nil || floats, [rule.name, rule.title].compactMap({ $0 }).allSatisfy(isPattern) else { continue }
                windowRules["aerospace-\(number + 1)"] =
                    WindowRule(appID: rule.app, app: rule.name, title: rule.title, floating: floats, workspace: floats ? nil : workspace)
                continue
            }
            guard let app = rule.app else { continue }
            if let workspace { workspaceRules[app] = workspace }
            if floats, !floating.contains(app) { floating.append(app) }
        }
        floatingApps = floating
    }

    static let gapNames = [
        "inner.horizontal": "inner_horizontal", "inner.vertical": "inner_vertical", "outer.left": "outer_left",
        "outer.right": "outer_right", "outer.bottom": "outer_bottom", "outer.top": "outer_top",
    ]

    /// The config edits that apply this on top of `settings`. Rules and
    /// floating apps are merged in; keys only when `keys` is set.
    public func changes(onto settings: Settings, keys: Bool) -> [String: SettingValue?] {
        var changes: [String: SettingValue?] = [:]
        func put(_ key: String, _ value: SettingValue) { changes[key] = Settings.entry(key, value) }
        for (key, v) in gaps { put(key, .number(v)) }
        if let layout { put("layout:default", .text(layout.rawValue)) }
        if let orientation { put("layout:orientation", .text(orientation.rawValue)) }
        if !workspaceRules.isEmpty {
            let merged = parseWorkspaceRules(settings.workspaceRules).merging(workspaceRules) { _, new in new }
            put("layout:workspace_rules", .text(formatWorkspaceRules(merged)))
        }
        if !floatingApps.isEmpty {
            var list = parseAppList(settings.floatingApps)
            list += floatingApps.filter { !list.contains($0) }
            put("layout:floating_apps", .text(list.joined(separator: ",")))
        }
        // Rules from an earlier import go first; the ones this import has are written over them.
        for name in settings.windowRules.keys where name.hasPrefix("aerospace-") {
            for field in WindowRule.fields { changes["rules:\(name):\(field)"] = .some(nil) }
        }
        for (name, rule) in windowRules {
            let fields: [String: SettingValue?] = [
                "app_id": rule.appID.map(SettingValue.text), "app": rule.app.map(SettingValue.text), "title": rule.title.map(SettingValue.text),
                "floating": rule.floating ? .flag(true) : nil, "workspace": rule.workspace.map { .number(Double($0)) },
            ]
            for (field, value) in fields { changes["rules:\(name):\(field)"] = value }
        }
        if autoBackAndForth { put("layout:auto_back_and_forth", .flag(true)) }
        if keys {
            for (chord, command) in bindings {
                if let c = KeyChord(chord) { changes["keys:\(c)"] = Settings.bindingEntry(c, command) }
            }
        }
        return changes
    }

    /// One line per kind of thing found, for the import dialog; `appName`
    /// turns a bundle id into the name to show.
    public func summary(appName: (String) -> String = { $0 }) -> [String] {
        var lines: [String] = []
        if !gaps.isEmpty {
            func pt(_ key: String) -> Int? { gaps["gaps:" + key].map { Int($0) } }
            var parts: [String] = []
            let inner = [pt("inner_horizontal"), pt("inner_vertical")]
            if inner[0] != nil, inner[0] == inner[1] {
                parts.append("\(inner[0]!) pt between windows")
            } else {
                parts += zip(inner, ["between windows side by side", "between windows above each other"]).compactMap { v, label in v.map { "\($0) pt \(label)" } }
            }
            let edges = ["outer_left", "outer_right", "outer_bottom", "outer_top"].map(pt)
            if edges[0] != nil, Set(edges).count == 1 {
                parts.append("\(edges[0]!) pt at the edges")
            } else {
                parts += zip(edges, ["at the left", "at the right", "at the bottom", "at the top"]).compactMap { v, label in v.map { "\($0) pt \(label)" } }
            }
            if let top = pt("outer_top_external"), top != pt("outer_top") { parts.append("\(top) pt at the top of other displays") }
            lines.append("Gaps: " + parts.joined(separator: ", ") + ".")
        }
        let names = [LayoutMode.tiles: "tiles", .stack: "a stack", .floating: "floating"]
        let orientations = [TileOrientation.auto: "automatic", .horizontal: "side by side", .vertical: "above each other"]
        if let layout {
            lines.append("New windows: \(names[layout]!)" + (orientation.map { ", \(orientations[$0]!) orientation" } ?? "") + ".")
        } else if let orientation {
            lines.append("Tiles: \(orientations[orientation]!) orientation.")
        }
        if !workspaceRules.isEmpty {
            let rules = workspaceRules.map { (appName($0.key), $0.value) }.sorted { ($0.1, $0.0) < ($1.1, $1.0) }
            lines.append("Workspace rules: " + rules.map { "\($0.0) → \($0.1)" }.joined(separator: ", ") + ".")
        }
        if !floatingApps.isEmpty { lines.append("Floating apps: " + floatingApps.map(appName).joined(separator: ", ") + ".") }
        if !windowRules.isEmpty {
            lines.append(counted(windowRules.count, "window rule") + " by app name or title.")
        }
        if autoBackAndForth { lines.append("Going to the workspace you are on goes back to the one before.") }
        if !bindings.isEmpty {
            let changed = bindings.filter { chord, command in KeyChord(chord).flatMap { Settings.bindingEntry($0, command) } != nil }.count
            lines.append(counted(bindings.count, "shortcut") + (changed == 0 ? ", all the same as mielwm's." : ", \(changed) of them different from mielwm's."))
        }
        return lines
    }
}

/// The one-time notice after a first-launch import from AeroSpace.
public func aeroSpaceImportNote(_ found: AeroSpaceImport) -> String {
    var parts: [String] = []
    if !found.gaps.isEmpty { parts.append("gaps") }
    if found.layout != nil || found.orientation != nil { parts.append("layout") }
    if !found.workspaceRules.isEmpty { parts.append(counted(found.workspaceRules.count, "workspace rule")) }
    if !found.floatingApps.isEmpty { parts.append(counted(found.floatingApps.count, "floating app")) }
    if found.autoBackAndForth { parts.append("workspace back and forth") }
    if !found.windowRules.isEmpty { parts.append(counted(found.windowRules.count, "window rule")) }
    let list = parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " and " + parts.last! : parts.joined()
    var place = "in Settings > Layout and Settings > Windows" // which don't edit window rules
    if !found.windowRules.isEmpty { place = parts.count == 1 ? "in the config file" : place + ", and window rules in the config file" }
    return "mielwm took your \(list) from AeroSpace's config. Change them any time \(place)."
}

/// "a,b" as ["a", "b"], blanks dropped.
public func parseAppList(_ text: String) -> [String] {
    text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

/// "com.a=1,com.b=2" as a dictionary; malformed pairs are dropped.
public func parseWorkspaceRules(_ text: String) -> [String: Int] {
    var rules: [String: Int] = [:]
    for pair in parseAppList(text) {
        let parts = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2, let n = Int(parts[1]), (1 ... 9).contains(n) { rules[parts[0]] = n }
    }
    return rules
}

public func formatWorkspaceRules(_ rules: [String: Int]) -> String {
    rules.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
}

// MARK: - AeroSpace names

/// "alt-shift-left" as a chord.
func aeroSpaceChord(_ key: String) -> KeyChord? {
    var parts = key.lowercased().split(separator: "-").map(String.init)
    guard let last = parts.popLast() else { return nil }
    let names = ["alt": "opt", "backtick": "grave", "leftsquarebracket": "leftbracket", "rightsquarebracket": "rightbracket",
                 "enter": "return", "esc": "escape", "backspace": "delete"]
    return KeyChord((parts.map { names[$0] ?? $0 } + [names[last] ?? last]).joined(separator: "+"))
}

/// An AeroSpace command as the mielwm action that does the same; nil if there is none.
/// `--auto-back-and-forth` is a setting in mielwm (layout:auto_back_and_forth).
func aeroSpaceCommand(_ command: String) -> String? {
    let words = command.split(separator: " ").map(String.init).filter { $0 != "--auto-back-and-forth" }
    let direction = words.count == 2 ? Direction(rawValue: words[1]) : nil
    let mapped: String? = switch words.first ?? "" {
    case "focus": direction.map { "focus \($0.rawValue)" }
    case "move": direction.map { "nudge \($0.rawValue)" }
    case "workspace" where words.count == 2: "workspace \(words[1])"
    case "move-node-to-workspace": words.last.map { "move-to-workspace \($0)" }
    case "layout" where words.count > 1:
        ["tiles": "layout tiles", "tiling": "layout tiles", "accordion": "layout stack", "floating": "layout floating"][words[1]]
    case "fullscreen" where words.count == 1: "fullscreen"
    case "resize" where words.count == 3 && words[1] == "smart" && ["-50", "+50"].contains(words[2]): // mielwm's ⌥- and ⌥=
        words[2] == "-50" ? "shrink" : "grow"
    case "resize" where words.count == 3: "resize \(words[1]) \(words[2])"
    case "workspace-back-and-forth" where words.count == 1: "workspace-back-and-forth"
    case "close" where words.count == 1: "close"
    case "macos-native-minimize" where words.count == 1: "minimize"
    default: nil
    }
    return mapped.flatMap { Action(command: $0) != nil ? $0 : nil }
}

// MARK: - The TOML subset

indirect enum TOMLValue: Equatable {
    case number(Double), string(String), bool(Bool), array([TOMLValue]), table([String: TOMLValue])

    /// A string, or the strings of an array.
    var strings: [String] {
        switch self {
        case let .string(s): [s]
        case let .array(items): items.compactMap { if case let .string(s) = $0 { s } else { nil } }
        default: []
        }
    }
}

/// A per-monitor gap ([{ monitor."built-in" = 12 }, 54]) as the built-in
/// display's value and everyone else's.
func gapValues(_ value: TOMLValue) -> (builtIn: Double?, other: Double?) {
    switch value {
    case let .number(n): return (n, n)
    case let .array(items):
        var builtIn: Double?, other: Double?
        for item in items {
            if case let .number(n) = item { other = n }
            if case let .table(t) = item {
                for (k, v) in t where k.lowercased().hasPrefix("monitor.") && k.lowercased().contains("built") {
                    if case let .number(n) = v { builtIn = n }
                }
            }
        }
        return (builtIn, other)
    default: return (nil, nil)
    }
}

/// Key-value lines with their table: `section` is the header's dotted path,
/// `block` counts `[[array tables]]` so their entries stay apart. A line it
/// can't read is skipped.
func parseTOML(_ text: String) -> [(section: String, block: Int, key: String, value: TOMLValue)] {
    var reader = TOMLReader(chars: Array(text))
    var entries: [(String, Int, String, TOMLValue)] = []
    var section = "", block = 0
    while true {
        reader.skip(newlines: true)
        guard let c = reader.peek else { break }
        if c == "[" {
            reader.i += 1
            let isArray = reader.eat("[")
            if let key = reader.key(), reader.eat("]"), !isArray || reader.eat("]") {
                section = key
                if isArray { block += 1 }
            }
        } else if let key = reader.key(), reader.eat("="), let value = reader.value() {
            entries.append((section, block, key, value))
        }
        reader.skipLine()
    }
    return entries
}

private struct TOMLReader {
    let chars: [Character]
    var i = 0

    var peek: Character? { i < chars.count ? chars[i] : nil }

    /// Spaces and comments; newlines too when asked.
    mutating func skip(newlines: Bool = false) {
        while let c = peek {
            if c == " " || c == "\t" || (newlines && (c == "\n" || c == "\r")) {
                i += 1
            } else if c == "#" {
                while let d = peek, d != "\n" { i += 1 }
            } else {
                break
            }
        }
    }

    mutating func skipLine() {
        while let c = peek, c != "\n" { i += 1 }
    }

    mutating func eat(_ c: Character) -> Bool {
        skip()
        guard peek == c else { return false }
        i += 1
        return true
    }

    /// `a.b`, `if.app-id`, `monitor."built-in"`, joined with dots, quotes gone.
    mutating func key() -> String? {
        var parts: [String] = []
        repeat {
            skip()
            if peek == "\"" || peek == "'" {
                guard case let .string(s)? = value() else { return nil }
                parts.append(s)
            } else {
                var part = ""
                while let c = peek, c.isLetter || c.isNumber || c == "_" || c == "-" { part.append(c); i += 1 }
                guard !part.isEmpty else { return nil }
                parts.append(part)
            }
            skip()
        } while eat(".")
        return parts.joined(separator: ".")
    }

    mutating func value() -> TOMLValue? {
        skip()
        guard let c = peek else { return nil }
        switch c {
        case "\"", "'": return string(quote: c)
        case "[":
            i += 1
            var items: [TOMLValue] = []
            while true {
                skip(newlines: true)
                if peek == "]" { i += 1; return .array(items) }
                guard let item = value() else { return nil }
                items.append(item)
                skip(newlines: true)
                if peek == "," { i += 1 }
            }
        case "{":
            i += 1
            var table: [String: TOMLValue] = [:]
            while true {
                skip()
                if peek == "}" { i += 1; return .table(table) }
                guard let k = key(), eat("="), let v = value() else { return nil }
                table[k] = v
                skip()
                if peek == "," { i += 1 }
            }
        case "t", "f":
            for word in ["true", "false"] where String(chars[i ..< min(i + word.count, chars.count)]) == word {
                i += word.count
                return .bool(word == "true")
            }
            return nil
        default:
            var text = ""
            while let d = peek, d.isNumber || "+-._eE".contains(d) { text.append(d); i += 1 }
            return Double(text.replacingOccurrences(of: "_", with: "")).map(TOMLValue.number)
        }
    }

    /// 'literal', "basic" with escapes, and the ''' / """ multi-line forms.
    private mutating func string(quote: Character) -> TOMLValue? {
        let triple = i + 2 < chars.count && chars[i + 1] == quote && chars[i + 2] == quote
        i += triple ? 3 : 1
        if triple, peek == "\n" { i += 1 } // a newline right after the opening quotes is not part of it
        var s = ""
        while let c = peek {
            if c == quote, !triple || (i + 2 < chars.count && chars[i + 1] == quote && chars[i + 2] == quote) {
                i += triple ? 3 : 1
                return .string(s)
            }
            if c == "\n", !triple { return nil }
            if c == "\\", quote == "\"", i + 1 < chars.count {
                let e = chars[i + 1]
                s.append(["n": "\n", "t": "\t", "\"": "\"", "\\": "\\"][e] ?? e)
                i += 2
                continue
            }
            s.append(c)
            i += 1
        }
        return nil
    }
}
