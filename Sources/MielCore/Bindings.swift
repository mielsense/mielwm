import Foundation

public extension Settings {
    /// What config.json holds for `chord` to do `command` (nil: nothing):
    /// nil (no entry) when that is the default, "none" to unbind a default.
    static func bindingEntry(_ chord: KeyChord, _ command: String?) -> SettingValue? {
        let standard = defaultBindings.first { KeyChord($0.key) == chord }?.value
        if standard.flatMap(Action.init(command:)) == command.flatMap(Action.init(command:)) { return nil }
        return .text(command ?? "none")
    }

    /// The modifiers of the chords that open the overview, when there are
    /// two or more of them: holding them warms the window captures, as the
    /// key is about to follow. One alone (⌥ for ⌥Space) is held for too
    /// many other things to start every capture each time.
    var warmModifiers: Set<Modifiers> {
        Set(chords.compactMap { chord, action in
            switch action {
            case .toggleOverview, .search, .help: chord.modifiers.rawValue.nonzeroBitCount >= 2 ? chord.modifiers : nil
            default: nil
            }
        })
    }

    /// The chords bound to `action`, in a stable order.
    func chords(for action: Action) -> [KeyChord] {
        chords.filter { $0.value == action }.map(\.key).sorted { $0.description < $1.description }
    }

    /// The config edits that move `action` from chord `old` to `new`
    /// (nil `old` adds a chord, nil `new` removes one).
    func rebind(_ action: Action, from old: KeyChord?, to new: KeyChord?) -> [String: SettingValue?] {
        var changes: [String: SettingValue?] = [:]
        if let old, old != new { changes["keys:\(old)"] = Settings.bindingEntry(old, nil) }
        if let new { changes["keys:\(new)"] = Settings.bindingEntry(new, action.command) }
        return changes
    }

    /// The config edits that give `action` (every action, for nil) its default chords back.
    func restoreDefaults(for action: Action?) -> [String: SettingValue?] {
        let standard = Settings()
        let affected = action.map { standard.chords(for: $0) + chords(for: $0) } ?? Array(standard.chords.keys) + Array(chords.keys)
        return Dictionary(affected.map { ("keys:\($0)", SettingValue?.none) }, uniquingKeysWith: { a, _ in a })
    }
}

/// Actions bound one per digit or arrow key under the same modifiers, which
/// the Settings window edits as one shortcut ("⌥1–9").
public enum ShortcutFamily: CaseIterable, Sendable {
    case workspace, moveToWorkspace, focus, nudge

    /// Each action with the key it goes on.
    public var members: [(action: Action, key: String)] {
        switch self {
        case .workspace: (1 ... 9).map { (.workspace($0), "\($0)") }
        case .moveToWorkspace: (1 ... 9).map { (.moveToWorkspace($0), "\($0)") }
        case .focus: Direction.allCases.map { (.focus($0), $0.rawValue) }
        case .nudge: Direction.allCases.map { (.nudge($0), $0.rawValue) }
        }
    }

    public var usesDigits: Bool { self == .workspace || self == .moveToWorkspace }

    public func contains(_ action: Action) -> Bool { members.contains { $0.action == action } }
}

/// How a family is bound: not at all, every member on its key under the same modifiers, or anything else.
public enum FamilyBinding: Hashable, Sendable {
    case none, modifiers(Modifiers), custom
}

public extension Settings {
    func binding(of family: ShortcutFamily) -> FamilyBinding {
        let bound = family.members.map { chords(for: $0.action) }
        if bound.allSatisfy(\.isEmpty) { return .none }
        guard let m = bound.first?.first?.modifiers else { return .custom }
        let uniform = zip(family.members, bound).allSatisfy { $1 == [KeyChord(modifiers: m, key: $0.key)] }
        return uniform ? .modifiers(m) : .custom
    }

    /// The config edits that put every member of `family` on its key under
    /// `modifiers`, dropping the chords it had (nil: no shortcuts at all).
    func rebind(_ family: ShortcutFamily, to modifiers: Modifiers?) -> [String: SettingValue?] {
        var changes: [String: SettingValue?] = [:]
        for member in family.members {
            for old in chords(for: member.action) { changes["keys:\(old)"] = Settings.bindingEntry(old, nil) }
        }
        for member in family.members {
            guard let modifiers else { break }
            let chord = KeyChord(modifiers: modifiers, key: member.key)
            changes["keys:\(chord)"] = Settings.bindingEntry(chord, member.action.command)
        }
        return changes
    }

    /// The config edits that give every member of `family` its default chords back.
    func restoreDefaults(for family: ShortcutFamily) -> [String: SettingValue?] {
        family.members.reduce(into: [:]) { changes, member in changes.merge(restoreDefaults(for: member.action)) { a, _ in a } }
    }

    /// The actions (not no-ops, not `mine`) already on `new` chords.
    func conflicts(_ new: [KeyChord], except mine: (Action) -> Bool) -> [(chord: KeyChord, action: Action)] {
        new.compactMap { c in chords[c].flatMap { $0 == .noop || mine($0) ? nil : (c, $0) } }
    }
}

public extension KeyChord {
    /// Every key name a chord can use.
    static var allKeys: Set<String> { keyNames }
}
