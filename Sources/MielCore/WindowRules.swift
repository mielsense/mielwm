import Foundation

// Rules by app name and window title, AeroSpace's on-window-detected with
// app-name-regex-substring and window-title-regex-substring. In config.json
// each rule is a named group, nested or flat:
//   "rules": { "pip": { "title": "Picture-in-Picture", "floating": true } }
//   "rules:pip:title": "Picture-in-Picture"
// Patterns are regular expressions found anywhere in the text, ignoring case.

public struct WindowRule: Hashable, Codable, Sendable {
    var appID: String? // bundle id, exact
    public var app: String? // pattern for the app name
    public var title: String? // pattern for the window title
    public var floating = false
    public var workspace: Int?

    /// The names config.json uses, after `rules:<name>:`.
    static let fields = ["app_id", "app", "title", "floating", "workspace"]

    public init(appID: String? = nil, app: String? = nil, title: String? = nil, floating: Bool = false, workspace: Int? = nil) {
        self.appID = appID
        self.app = app
        self.title = title
        self.floating = floating
        self.workspace = workspace
    }

    /// Every matcher it has fits. A rule with no matcher, or nothing to do, matches nothing.
    func matches(_ s: WindowSnapshot) -> Bool {
        guard appID != nil || app != nil || title != nil, floating || workspace != nil else { return false }
        if let appID, s.bundleID?.lowercased() != appID.lowercased() { return false }
        return Self.finds(app, in: s.appName) && Self.finds(title, in: s.title)
    }

    private static func finds(_ pattern: String?, in text: String) -> Bool {
        pattern.map { text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil } ?? true
    }
}

extension Settings {
    /// Sets one field from a `rules:<name>:<field>` entry. Returns an error message instead when it can't.
    mutating func setRule(_ key: String, _ value: SettingValue) -> String? {
        let parts = key.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { return "'\(key)' needs the form rules:<name>:<field>" }
        var rule = windowRules[parts[1]] ?? WindowRule()
        let invalid = "'\(key)' is not a valid regular expression"
        switch (parts[2], value) {
        case let ("app_id", .text(t)): rule.appID = t
        case let ("app", .text(t)): guard isPattern(t) else { return invalid }; rule.app = t
        case let ("title", .text(t)): guard isPattern(t) else { return invalid }; rule.title = t
        case let ("floating", .flag(b)): rule.floating = b
        case let ("workspace", .number(n)) where (1 ... 9).contains(n) && n == n.rounded(): rule.workspace = Int(n)
        case (let field, _) where WindowRule.fields.contains(field): return "'\(key)' has the wrong type"
        default: return "'\(key)': a rule takes app, title, app_id, floating and workspace"
        }
        windowRules[parts[1]] = rule
        return nil
    }

    /// The first rule, by name with numbers in order (rule-2 before rule-10), that matches the window.
    func windowRule(for s: WindowSnapshot) -> WindowRule? {
        windowRules.sorted { $0.key.compare($1.key, options: .numeric) == .orderedAscending }.first { $0.value.matches(s) }?.value
    }
}

/// A regular expression rules can use.
func isPattern(_ text: String) -> Bool { (try? NSRegularExpression(pattern: text)) != nil }
