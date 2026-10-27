import Foundation
@testable import MielCore
import Testing

private func paths(_ dir: URL) -> ConfigPaths {
    ConfigPaths(config: dir.appendingPathComponent("config.json"))
}

private func object(_ url: URL) throws -> NSDictionary {
    try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! NSDictionary
}

// MARK: Writing config.json

@Test func writerKeepsWhatItDoesNotTouch() throws {
    let p = paths(try tempDir())
    try json("""
    {
      // the user's note
      "distortion": {"strength": 0.2, "vignette": 0.3},
      "my:own": [1, 2],
      "keys:alt+o": "none"
    }
    """).write(to: p.config)
    try updateConfig(["distortion:strength": .number(0.1), "canvas:grid_enabled": .flag(false), "keys:opt+o": nil], paths: p)
    let o = try object(p.config)
    #expect(o["distortion"] as? NSDictionary == ["vignette": 0.3]) // the nested spelling is replaced, its sibling stays
    #expect(o["distortion:strength"] as? Double == 0.1 && o["canvas:grid_enabled"] as? Bool == false)
    #expect(o["my:own"] as? [Int] == [1, 2])
    #expect(o["keys:alt+o"] == nil) // another spelling of the same chord
    let loaded = loadSettings(p)
    #expect(loaded.errors.count == 1) // my:own is not a setting
    #expect(loaded.settings.look.lensStrength == 0.1 && !loaded.settings.look.gridEnabled)
    #expect(loaded.settings.chords[KeyChord("opt+o")!] == .pin) // the unbinding is gone: default again
}

@Test func writerRefusesBrokenJSON() throws {
    let p = paths(try tempDir())
    try json("{ nope").write(to: p.config)
    #expect(throws: ConfigWriteError.self) { try updateConfig(["canvas:grid_enabled": .flag(false)], paths: p) }
    #expect(try String(contentsOf: p.config, encoding: .utf8) == "{ nope")
}

@Test func defaultValuesLeaveNoEntry() {
    #expect(Settings.entry("canvas:initial_zoom", .number(0.72)) == nil)
    #expect(Settings.entry("canvas:initial_zoom", .number(0.5)) == .number(0.5))
    #expect(Settings.entry("layout:default", .text("stack")) == .text("stack"))
    #expect(Settings.entry("layout:default", .text("tiles")) == nil)
}

// MARK: Bindings through the writer

@Test func rebindingRoundTrips() throws {
    let p = paths(try tempDir())
    func settings() -> Settings { loadSettings(p).settings }
    // Move overview from ⌃⌥G to ⌘⌥O: the default chord is unbound, the new one bound.
    try updateConfig(settings().rebind(.toggleOverview, from: KeyChord("ctrl+opt+g"), to: KeyChord("cmd+opt+o")), paths: p)
    #expect(try object(p.config) == ["keys:ctrl+opt+g": "none", "keys:opt+cmd+o": "overview"])
    #expect(settings().chords(for: .toggleOverview) == [KeyChord("cmd+opt+o")!])
    #expect(loadSettings(p).errors.isEmpty)

    // A second chord for fill, then drop the default one.
    try updateConfig(settings().rebind(.fill, from: nil, to: KeyChord("ctrl+opt+return")), paths: p)
    #expect(Set(settings().chords(for: .fill)) == [KeyChord("opt+t")!, KeyChord("ctrl+opt+return")!])

    // Taking a chord another action has: it moves.
    try updateConfig(settings().rebind(.pin, from: nil, to: KeyChord("opt+t")), paths: p)
    #expect(settings().chords[KeyChord("opt+t")!] == .pin && settings().chords(for: .fill) == [KeyChord("ctrl+opt+return")!])

    // Restore one action, then everything.
    try updateConfig(settings().restoreDefaults(for: .toggleOverview), paths: p)
    #expect(settings().chords(for: .toggleOverview) == [KeyChord("ctrl+opt+g")!])
    #expect(try object(p.config)["keys:ctrl+opt+g"] == nil)
    try updateConfig(settings().restoreDefaults(for: nil), paths: p)
    #expect(try object(p.config) == [:])
    #expect(settings() == Settings())
}

@Test func bindingEntriesFollowTheDefaults() {
    let g = KeyChord("ctrl+opt+g")!, q = KeyChord("ctrl+opt+q")!
    #expect(Settings.bindingEntry(g, "overview") == nil)
    #expect(Settings.bindingEntry(g, nil) == .text("none"))
    #expect(Settings.bindingEntry(g, "fit") == .text("fit"))
    #expect(Settings.bindingEntry(q, nil) == nil)
    #expect(Settings.bindingEntry(KeyChord("opt+comma")!, "layout accordion") == nil) // same action, other name
}

// MARK: Shortcut families

@Test func familiesReadAsOneShortcut() {
    var s = Settings()
    #expect(s.binding(of: .workspace) == .modifiers(.option) && s.binding(of: .moveToWorkspace) == .modifiers([.option, .shift]))
    #expect(s.binding(of: .focus) == .modifiers(.option) && s.binding(of: .nudge) == .modifiers([.option, .shift]))
    s.bindings["opt+3"] = nil
    #expect(s.binding(of: .workspace) == .custom) // one key missing
    s.bindings["ctrl+3"] = "workspace 3"
    #expect(s.binding(of: .workspace) == .custom) // one key elsewhere
    for n in 1 ... 9 { s.bindings["opt+\(n)"] = nil; s.bindings["ctrl+\(n)"] = nil }
    #expect(s.binding(of: .workspace) == .none)
}

@Test func familyRebindingWritesEveryKey() throws {
    let p = paths(try tempDir())
    func settings() -> Settings { loadSettings(p).settings }
    try updateConfig(settings().rebind(.workspace, to: [.control, .option]), paths: p)
    #expect(settings().binding(of: .workspace) == .modifiers([.control, .option]))
    #expect(settings().chords[KeyChord("opt+4")!] == nil && settings().chords[KeyChord("ctrl+opt+4")!] == .workspace(4))
    #expect(try object(p.config).count == 18) // nine unbound, nine bound
    #expect(loadSettings(p).errors.isEmpty)

    // Cleared, then back to the defaults: nothing left in the file.
    try updateConfig(settings().rebind(.focus, to: nil), paths: p)
    #expect(settings().binding(of: .focus) == .none && settings().chords[KeyChord("opt+left")!] == nil)
    try updateConfig(settings().restoreDefaults(for: .focus), paths: p)
    try updateConfig(settings().rebind(.workspace, to: .option), paths: p)
    #expect(try object(p.config) == [:])
    #expect(settings() == Settings())

    // ⌃+arrows would take the workspace keys: those are the conflicts, not focus's own.
    let new = ShortcutFamily.focus.members.map { KeyChord(modifiers: .control, key: $0.key) }
    let conflicts = settings().conflicts(new, except: ShortcutFamily.focus.contains)
    #expect(conflicts.map(\.action) == [.workspaceStep(forward: false), .workspaceStep(forward: true)])
    #expect(settings().conflicts([KeyChord("opt+0")!], except: { _ in false }).isEmpty) // no-ops give way
}

@Test func defaultsHaveNoDuplicates() {
    let s = Settings()
    #expect(s.chords(for: .fill) == [KeyChord("opt+t")!]) // ⌥⌘F is gone
    #expect(s.chords.filter { $0.value == .noop }.keys.map(\.description).sorted() == ["opt+0", "opt+semicolon", "opt+shift+0"])
    // An old config that names the dropped chord still loads.
    let old = parseSettings(config: json(#"{"keys:opt+cmd+f": "none", "keys:opt+cmd+g": "fill"}"#))
    #expect(old.errors.isEmpty && old.settings.chords(for: .fill).count == 2)
}

@Test func menuBarIndicatorIsASetting() {
    #expect(Settings().menuBarWorkspaces)
    let off = parseSettings(config: json(#"{"menubar": {"workspaces": false}}"#))
    #expect(off.errors.isEmpty && !off.settings.menuBarWorkspaces)
    #expect(Settings.entry("menubar:workspaces", .flag(true)) == nil)
}

@Test func writerKeepsASymlinkedConfig() throws {
    let dir = try tempDir(), fm = FileManager.default
    let real = dir.appendingPathComponent("dotfiles/config.json"), p = paths(dir.appendingPathComponent("mielwm"))
    try fm.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fm.createDirectory(at: p.config.deletingLastPathComponent(), withIntermediateDirectories: true)
    try json("{}").write(to: real)
    try fm.createSymbolicLink(at: p.config, withDestinationURL: real)
    try updateConfig(["canvas:grid_enabled": .flag(false)], paths: p)
    #expect(try fm.destinationOfSymbolicLink(atPath: p.config.path) == real.path)
    #expect(try object(real) == ["canvas:grid_enabled": false])
}
