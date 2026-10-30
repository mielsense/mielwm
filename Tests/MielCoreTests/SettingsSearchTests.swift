import Foundation
import Testing

// The Settings sidebar's search finds a pane by the keywords in SettingsPane.swift.
// Those are kept by hand, so this reads each pane's source and checks that every
// title it draws is in its pane's keywords. It lives here because the app target
// can't be imported by tests; it only reads files.

private let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Sources/mielwm").standardized

private let paneFiles: [String: [String]] = [
    "general": ["GeneralPane"], "layout": ["LayoutPane"], "windows": ["WindowsPane"], "overview": ["OverviewPane"],
    "keyboard": ["KeyboardPane"], "trackpad": ["TrackpadPane"], "appearance": ["AppearancePane"], "menubar": ["MenuBarPane"],
    "integrations": ["IntegrationsPane"], "advanced": ["AdvancedPane"], "about": ["AboutPane"],
]

/// Shown but not settings: a status under an app's name, and the shortcut search's own placeholder.
private let notTitles: Set<String> = ["Not installed", "Search shortcuts"]

private func read(_ name: String) throws -> String {
    try String(contentsOf: sources.appendingPathComponent(name + ".swift"), encoding: .utf8)
}

/// The literal titles a view file draws: what Text, Toggle, Section, Picker, LabeledContent,
/// LabeledSlider and SettingsRow start with, and `title:` arguments. Sentences and
/// interpolations are not titles.
private func titles(in source: String) -> Set<String> {
    // After a constructor or `title:`, either a literal or a choice between two: `x ? "A" : "B"`.
    let pattern = #"(?:\b(?:Text|Toggle|Section|Picker|LabeledContent|LabeledSlider|SettingsRow)\(|\btitle: )(?:[^"\n,]*\? "([^"\\]+)" : )?"([^"\\]+)""#
    let regex = try! NSRegularExpression(pattern: pattern)
    let range = NSRange(source.startIndex..., in: source)
    return Set(regex.matches(in: source, range: range).flatMap { m in
        [1, 2].compactMap { Range(m.range(at: $0), in: source).map { String(source[$0]) } }
    }.filter { $0.first?.isUppercase == true && !$0.hasSuffix(".") && !notTitles.contains($0) })
}

/// Each pane's keywords as written in SettingsPane.swift: the string literals after `case .pane:`
/// in `var keywords`, up to the next case.
private func keywords() throws -> [String: [String]] {
    let source = try read("SettingsPane")
    guard let start = source.range(of: "var keywords: [String] {"), let end = source.range(of: "\n    }\n", range: start.upperBound ..< source.endIndex) else { return [:] }
    let body = source[start.upperBound ..< end.lowerBound]
    var found: [String: [String]] = [:]
    for arm in body.components(separatedBy: "case .").dropFirst() {
        let name = String(arm.prefix { $0.isLetter })
        let literal = try NSRegularExpression(pattern: #""([^"\\]+)""#)
        found[name] = literal.matches(in: arm, range: NSRange(arm.startIndex..., in: arm)).compactMap { m in
            Range(m.range(at: 1), in: arm).map { String(arm[$0]) }
        }
    }
    return found
}

@Test func searchFindsEveryTitleAPaneDraws() throws {
    let words = try keywords()
    #expect(Set(words.keys) == Set(paneFiles.keys), "every pane has keywords")
    for (pane, files) in paneFiles {
        let shown = try files.map(read).reduce(into: Set<String>()) { $0.formUnion(titles(in: $1)) }
        #expect(!shown.isEmpty, "\(pane) draws titles")
        let missing = shown.filter { title in !(words[pane] ?? []).contains { $0.localizedStandardContains(title) } }
        #expect(missing.isEmpty, "\(pane) keywords miss \(missing.sorted())")
    }
}

/// mielwm works with any app built for AeroSpace: its text names Barik only as an example
/// ("like Barik"), and search still takes "Barik" to the AeroSpace pane.
@Test func barikIsOnlyAnExample() throws {
    // Multi-line strings whole, then one-line ones with their escapes.
    let literal = try NSRegularExpression(pattern: #"(?s)"""(.*?)"""|"((?:[^"\\\n]|\\.)*)""#)
    for file in ["IntegrationsPane", "MenuBarPane", "AppDelegate+Barik", "SettingsPane", "AppDelegate+Menu", "Onboarding"] {
        let source = try read(file)
        let strings = literal.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap { m in
            (Range(m.range(at: 1), in: source) ?? Range(m.range(at: 2), in: source)).map { String(source[$0]) }
        }
        let named = strings.filter { $0.contains("Barik") && !$0.contains("like Barik") && $0 != "Barik" }
        #expect(named.isEmpty, "\(file): \(named)")
    }
    #expect(try keywords()["integrations"]?.contains("Barik") == true)
}
