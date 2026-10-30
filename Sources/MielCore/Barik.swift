import Foundation

// Barik, a menu bar, shows AeroSpace's workspaces by running the `aerospace`
// command. mielwm's own `aerospace` command (docs/aerospace.md) asks the
// running app, which answers here from the canvas.

// MARK: - Barik's AeroSpace commands

/// What the app does with one `aerospace` command.
public enum AeroSpaceReply: Equatable, Sendable {
    case output(String) // a JSON array to print
    case input(CoreInput?) // an action to take (nil: its window is gone); prints nothing
    case unknown
}

public extension CanvasState {
    /// The commands Barik runs. Workspaces are named by slot number, windows by their CGWindowID.
    func aerospace(_ args: [String]) -> AeroSpaceReply {
        let flags = Set(args.dropFirst()), focusedOnly = flags.contains("--focused")
        let listing = flags.contains("--json") && (focusedOnly || flags.contains("--all"))
        switch args.first {
        case "list-workspaces" where listing:
            let slots = focusedOnly ? [currentWorkspace].compactMap { $0 } : workspaces.map(\.slot).sorted()
            return .output(aeroJSON(slots.map { ["workspace": String($0)] }))
        case "list-windows" where listing:
            // Floating windows belong to no workspace; Barik lists windows by workspace.
            let listed = focusedOnly ? windows.filter { $0.id == focused } : windows.filter { $0.workspace != nil }
            return .output(aeroJSON(listed.map(AeroWindow.init)))
        case "workspace" where args.count == 2:
            guard let n = Int(args[1]) else { return .unknown }
            return .input(.action(.workspace(n)))
        case "focus" where args.count == 3 && args[1] == "--window-id":
            guard let n = UInt32(args[2]) else { return .unknown }
            return .input(windows.first { $0.id.number == n }.map { .landOn($0.id) })
        case "workspace-back-and-forth", "close", "macos-native-minimize", "resize", "focus":
            // The commands that do here what they do in AeroSpace, by the same words. Not through
            // aeroSpaceCommand: the import maps ±50 to ⌥= and ⌥-, and its move and layout aren't AeroSpace's.
            let command = args == ["macos-native-minimize"] ? "minimize" : args.joined(separator: " ")
            return Action(command: command).map { .input(.action($0)) } ?? .unknown
        default:
            return .unknown
        }
    }
}

/// One window as `aerospace list-windows --json` prints it.
private struct AeroWindow: Encodable {
    var id: UInt32, app: String, title: String, workspace: String?

    enum CodingKeys: String, CodingKey {
        case id = "window-id", app = "app-name", title = "window-title", workspace
    }
}

private extension AeroWindow {
    init(_ w: ManagedWindow) {
        self.init(id: w.id.number, app: w.appName, title: w.title, workspace: w.workspace.map(String.init))
    }
}

private func aeroJSON(_ value: some Encodable) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
}

// MARK: - Barik's config

/// Points Barik's `aerospace.path` at mielwm's command and back. Edits that
/// one line and leaves every other line, comment and blank as it was.
public enum BarikConfig {
    /// The files Barik reads, in its order: it uses the first that exists.
    public static func candidates(home: URL) -> [URL] {
        [home.appendingPathComponent(".barik-config.toml"), home.appendingPathComponent(".config/barik/config.toml")]
    }

    /// How tall Barik draws its bar, from experimental.foreground.height: a
    /// number, "menu-bar" (`menuBar`), or Barik's default of 55. Barik's
    /// window covers the whole display, so its size does not say.
    public static func barHeight(_ text: String, menuBar: Double) -> Double {
        for entry in parseTOML(text) where (entry.section.isEmpty ? entry.key : entry.section + "." + entry.key) == "experimental.foreground.height" {
            if case let .number(n) = entry.value { return n }
            if case .string("menu-bar") = entry.value { return menuBar }
        }
        return 55
    }

    /// `text` with aerospace.path set to `path`, and the value it had, as
    /// written in the file (nil: it had none, or it was mielwm's command,
    /// then `wasMielwm`). nil when aerospace is set in a form this does not
    /// edit (an inline table).
    public static func pointing(_ text: String, to path: String) -> (text: String, previous: String?, wasMielwm: Bool)? {
        let scan = Scan(text)
        guard !scan.inlineTable else { return nil }
        var lines = scan.lines
        if let found = scan.path, let value = scan.pathValue {
            lines[found.line].replaceSubrange(found.value, with: quoted(path))
            let mielwm = isMielwm(value)
            return (lines.joined(separator: "\n"), mielwm ? nil : value, mielwm)
        }
        if let table = scan.aerospaceTable {
            lines.insert("path = \(quoted(path))", at: table + 1)
        } else if let header = scan.firstHeader {
            lines.insert(contentsOf: ["aerospace.path = \(quoted(path))", ""], at: header)
        } else {
            lines.insert("aerospace.path = \(quoted(path))", at: lines.last == "" ? lines.count - 1 : lines.count)
        }
        return (lines.joined(separator: "\n"), nil, false)
    }

    /// Undoes `pointing`: puts `previous` back, or removes the line. Leaves
    /// the text alone when aerospace.path no longer is `path` or another
    /// copy's command.
    public static func restoring(_ text: String, from path: String, previous: String?) -> String {
        let scan = Scan(text)
        guard let found = scan.path, let value = scan.pathValue, value == quoted(path) || isMielwm(value) else { return text }
        var lines = scan.lines
        if let previous {
            lines[found.line].replaceSubrange(found.value, with: previous)
        } else {
            lines.remove(at: found.line)
            // The blank line `pointing` put between it and the first table.
            if found.topLevel, lines.indices.contains(found.line + 1), lines[found.line].isEmpty,
               lines[found.line + 1].trimmingCharacters(in: .whitespaces).hasPrefix("[") {
                lines.remove(at: found.line)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// A value, as written in the file, naming the `aerospace` command of
    /// any copy of mielwm.app: the app's path changes when it moves.
    static func isMielwm(_ value: String) -> Bool {
        value.hasSuffix("/Contents/Helpers/aerospace\"") || value.hasSuffix("/Contents/Helpers/aerospace'")
    }

    static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Where aerospace is set in a TOML file, read line by line.
    // shortcut: no multi-line strings ("""), which Barik's configs don't use; a full TOML parser if they ever do.
    private struct Scan {
        var lines: [String]
        var path: (line: Int, value: Range<String.Index>, topLevel: Bool)?
        var aerospaceTable: Int?
        var firstHeader: Int?
        var inlineTable = false
        /// aerospace.path's value as written in the file.
        var pathValue: String? { path.map { String(lines[$0.line][$0.value]) } }

        init(_ text: String) {
            lines = text.components(separatedBy: "\n")
            var table: String? // nil: top level
            var depth = 0 // brackets still open in a multi-line array
            for (i, line) in lines.enumerated() {
                if depth > 0 { depth += bracketDepth(line[...]); continue }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("[") {
                    let name = trimmed.hasPrefix("[[") ? "[[" : trimmed.dropFirst().prefix { $0 != "]" }
                        .trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
                    table = name
                    firstHeader = firstHeader ?? i
                    if name == "aerospace" { aerospaceTable = i }
                    continue
                }
                guard !trimmed.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
                let key = line[..<eq].filter { !$0.isWhitespace }
                let value = Self.value(in: line, after: eq)
                if (table == nil && key == "aerospace.path") || (table == "aerospace" && key == "path") {
                    path = (i, value, table == nil)
                }
                if table == nil, key == "aerospace" { inlineTable = true }
                depth += bracketDepth(line[value.lowerBound...])
            }
        }

        /// The value's range: a quoted string, else up to a space or a comment.
        static func value(in line: String, after eq: String.Index) -> Range<String.Index> {
            let start = line[line.index(after: eq)...].firstIndex { $0 != " " && $0 != "\t" } ?? line.endIndex
            var i = start
            if i < line.endIndex, line[i] == "\"" || line[i] == "'" {
                let quote = line[i]
                i = line.index(after: i)
                while i < line.endIndex, line[i] != quote {
                    if quote == "\"", line[i] == "\\", line.index(after: i) < line.endIndex { i = line.index(after: i) }
                    i = line.index(after: i)
                }
                return start ..< (i < line.endIndex ? line.index(after: i) : i)
            }
            while i < line.endIndex, !" \t#\r".contains(line[i]) { i = line.index(after: i) }
            return start ..< i
        }
    }
}

/// Opened minus closed brackets outside strings and comments.
private func bracketDepth(_ s: Substring) -> Int {
    var depth = 0, quote: Character?, escaped = false
    for c in s {
        if let q = quote {
            if escaped { escaped = false } else if c == "\\", q == "\"" { escaped = true } else if c == q { quote = nil }
        } else if c == "\"" || c == "'" { quote = c } else if c == "#" { break } else if c == "[" { depth += 1 } else if c == "]" { depth -= 1 }
    }
    return depth
}
