import AppKit
import Carbon.HIToolbox
import MielCore
import MielSystem
import SwiftUI

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
private func memberName(_ action: Action) -> String {
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

private let defaults = MielCore.Settings()

// MARK: - Recording

extension SettingsModel {
    func startRecording(_ slot: ShortcutSlot) {
        conflict = nil
        recording = slot
    }

    /// Installs or removes the key monitor as `recording` changes.
    func recordingChanged() {
        if recording != nil, keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                nonisolated(unsafe) let event = event // monitors run on the main thread
                let consumed = MainActor.assumeIsolated { self?.record(event) ?? false }
                return consumed ? nil : event
            }
            onRecording(true)
        } else if recording == nil, let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
            held = []
            onRecording(false)
        }
    }

    /// Esc cancels, Delete clears, any other chord sets it. A family takes
    /// the modifiers held when one of its keys (or Return) goes down. True: the key is used up.
    private func record(_ event: NSEvent) -> Bool {
        guard let slot = recording else { return false }
        let mods = Modifiers(event.modifierFlags)
        if event.type == .flagsChanged {
            held = mods
            return false
        }
        let code = Int(event.keyCode)
        if mods.isEmpty, code == kVK_Escape {
            recording = nil
            return true
        }
        if mods.isEmpty, code == kVK_Delete || code == kVK_ForwardDelete {
            recording = nil
            switch slot.target {
            case let .action(action): if let old = slot.chord { apply(settings.rebind(action, from: old, to: nil)) }
            case let .family(family): apply(settings.rebind(family, to: nil))
            }
            return true
        }
        guard let key = Self.keyNames[event.keyCode] else {
            NSSound.beep()
            return true
        }
        switch slot.target {
        case let .family(family):
            // ⇧ alone would take the digits or arrows from typing.
            guard key == "return" || family.members.contains(where: { $0.key == key }), !mods.subtracting(.shift).isEmpty else {
                NSSound.beep()
                return true
            }
            recording = nil
            guard settings.binding(of: family) != .modifiers(mods) else { return true }
            propose(slot, settings.rebind(family, to: mods), family.members.map { KeyChord(modifiers: mods, key: $0.key) }, mine: family.contains)
        case let .action(action):
            // A plain letter would stop typing it anywhere; F-keys are fine alone. ⌘ plus quit, close and edit keys would be swallowed in every app.
            guard !mods.subtracting(.shift).isEmpty || Self.isFunctionKey(key),
                  !(mods == [.command] && ["q", "w", "c", "v", "x", "z", "a", "s", "tab", "space", "h", "m"].contains(key)) else {
                NSSound.beep()
                return true
            }
            recording = nil
            let chord = KeyChord(modifiers: mods, key: key)
            guard chord != slot.chord else { return true }
            propose(slot, settings.rebind(action, from: slot.chord, to: chord), [chord], mine: { $0 == action })
        }
        return true
    }

    /// Applies `changes`, unless other actions have those chords: then asks first.
    private func propose(_ slot: ShortcutSlot, _ changes: [String: SettingValue?], _ chords: [KeyChord], mine: (Action) -> Bool) {
        let taken = settings.conflicts(chords, except: mine)
        guard !taken.isEmpty else { return apply(changes) }
        conflict = ShortcutConflict(slot: slot, changes: changes, chords: taken.map(\.chord), others: taken.map(\.action))
    }

    static let keyNames: [UInt16: String] = Dictionary(
        KeyChord.allKeys.compactMap { name in Chord(name).map { ($0.keyCode, name) } }, uniquingKeysWith: { a, _ in a })

    static func isFunctionKey(_ key: String) -> Bool { key.count > 1 && key.hasPrefix("f") && Int(key.dropFirst()) != nil }
}

extension Modifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.command) { insert(.command) }
    }

    /// ⌃⌥⇧⌘, in the system's order.
    var symbols: String {
        [(Modifiers.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")].filter { contains($0.0) }.map(\.1).joined()
    }
}

extension ShortcutFamily {
    /// "1–9" or "←→↑↓": the keys after the modifiers.
    var keysSymbol: String { usesDigits ? "1–9" : "←→↑↓" }
}

// MARK: - Views

struct KeyboardPane: View {
    @EnvironmentObject var model: SettingsModel

    var body: some View {
        let listed = Set(shortcutGroups.flatMap(\.items).flatMap { item -> [Action] in
            switch item.target {
            case let .action(a): [a]
            case let .family(f): f.members.map(\.action)
            }
        })
        let others = Set(model.settings.chords.values).subtracting(listed).subtracting([.noop])
            .sorted { actionName($0).localizedStandardCompare(actionName($1)) == .orderedAscending }
        Form {
            ForEach(Array(shortcutGroups.enumerated()), id: \.offset) { index, group in
                Section {
                    ForEach(group.items, id: \.name) { item in
                        switch item.target {
                        case let .action(action): ShortcutRow(action: action, name: item.name, detail: item.detail)
                        case let .family(family): FamilyRow(family: family, name: item.name, detail: item.detail)
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 14) {
                        // Said once, above the first shortcut it applies to.
                        if index == 0 { Text("Click a shortcut, then press the new keys. Esc cancels, Delete clears it.").settingsFooter() }
                        Text(group.title)
                    }
                }
            }
            if !others.isEmpty {
                Section {
                    ForEach(others, id: \.self) { ShortcutRow(action: $0, name: actionName($0), detail: nil) }
                } header: {
                    Text("From config.json")
                }
            }
            Section {
                ForEach(overviewKeys, id: \.keys) { key in
                    LabeledContent(key.name) { KeyCaps(text: key.keys) }
                }
            } header: {
                Text("In the overview")
            } footer: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Press ⌘/ in the overview for every key.").settingsFooter()
                    Button("Restore defaults…") { model.confirmRestoreShortcuts = true }
                        .disabled(model.settings.bindings == defaults.bindings)
                }
            }
        }
        .confirmationDialog("Restore every shortcut?", isPresented: $model.confirmRestoreShortcuts) {
            Button("Restore defaults") { model.apply(model.settings.restoreDefaults(for: nil)) }
        } message: {
            Text("Every action gets its default shortcut back.")
        }
    }
}

/// An action with its shortcuts, one recorder each, or an empty recorder.
struct ShortcutRow: View {
    let action: Action
    let name: String
    let detail: String?
    @EnvironmentObject var model: SettingsModel

    var body: some View {
        let chords = model.settings.chords(for: action)
        let changed = chords != defaults.chords(for: action)
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent {
                HStack(spacing: 6) {
                    RestoreButton(visible: changed) { model.apply(model.settings.restoreDefaults(for: action)) }
                    ForEach(chords, id: \.self) { ShortcutRecorder(slot: ShortcutSlot(target: .action(action), chord: $0)) }
                    if chords.isEmpty { ShortcutRecorder(slot: ShortcutSlot(target: .action(action), chord: nil)) }
                }
            } label: {
                Text(name)
                if let detail { Text(detail) }
            }
            ShortcutNotes(target: .action(action), chords: chords)
        }
    }
}

/// A family as one shortcut ("⌥1–9"); when its keys differ, "Custom", and a
/// disclosure with a row per key.
struct FamilyRow: View {
    let family: ShortcutFamily
    let name: String
    let detail: String?
    @EnvironmentObject var model: SettingsModel

    var body: some View {
        let binding = model.settings.binding(of: family)
        let open = binding == .custom && model.expanded.contains(family)
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent {
                HStack(spacing: 6) {
                    RestoreButton(visible: binding != defaults.binding(of: family)) { model.apply(model.settings.restoreDefaults(for: family)) }
                    ShortcutRecorder(slot: ShortcutSlot(target: .family(family), chord: nil))
                }
            } label: {
                HStack(spacing: 4) {
                    if binding == .custom {
                        Button {
                            if open { model.expanded.remove(family) } else { model.expanded.insert(family) }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(open ? 90 : 0))
                                .frame(width: 14, height: 14)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(open ? "Hide each key" : "Show each key")
                        .accessibilityLabel(open ? "Hide each key" : "Show each key")
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                        if let detail { Text(detail).font(.callout).foregroundStyle(.secondary) }
                    }
                }
            }
            ShortcutNotes(target: .family(family), chords: family.members.flatMap { model.settings.chords(for: $0.action) })
        }
        if open {
            ForEach(family.members, id: \.key) { member in
                ShortcutRow(action: member.action, name: memberName(member.action), detail: nil)
                    .padding(.leading, 18)
            }
        }
    }
}

/// Under a row: a conflict waiting for an answer, or what macOS also does with its keys.
struct ShortcutNotes: View {
    let target: ShortcutTarget
    let chords: [KeyChord]
    @EnvironmentObject var model: SettingsModel

    var body: some View {
        if let c = model.conflict, c.slot.target == target {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(conflictText(c)).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Cancel") { model.conflict = nil }
                Button("Use here") {
                    model.conflict = nil
                    model.apply(c.changes)
                }
                .keyboardShortcut(.defaultAction)
            }
            .font(.callout)
            .controlSize(.small)
        } else {
            let notes = Array(Set(chords.compactMap(systemUse))).sorted()
            ForEach(notes, id: \.self) { note in
                Label(note, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "⌃← and ⌃→ already do “Previous workspace” and “Next workspace”."
    private func conflictText(_ c: ShortcutConflict) -> String {
        func list(_ items: [String]) -> String {
            items.count < 2 ? items.joined() : items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
        var names: [String] = []
        for name in c.others.map(actionName) where !names.contains(name) { names.append(name) }
        return "\(list(c.chords.map(\.symbol))) already \(c.chords.count == 1 ? "does" : "do") \(list(names.map { "“\($0)”" }))."
    }
}

/// A shortcut in a field like the system's: click to record, then press keys.
struct ShortcutRecorder: View {
    let slot: ShortcutSlot
    @EnvironmentObject var model: SettingsModel

    var body: some View {
        let recording = model.recording == slot
        let (text, dim) = label(recording: recording)
        Button { recording ? (model.recording = nil) : model.startRecording(slot) } label: {
            Text(text)
                .foregroundStyle(dim ? .secondary : .primary)
                .lineLimit(1)
                .frame(minWidth: 96)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(recording ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: recording ? 2 : 1))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.accentColor.opacity(recording ? 0.3 : 0), lineWidth: 3).padding(-3))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(recording ? hint : "Click to change")
        .accessibilityLabel(recording ? "Recording a shortcut" : "Shortcut: \(text)")
        .accessibilityHint(hint)
    }

    private var hint: String {
        if case .family = slot.target { return "Hold the modifiers and press one of the keys. Esc cancels, Delete clears it." }
        return "Press the new keys. Esc cancels, Delete clears it."
    }

    private func label(recording: Bool) -> (String, Bool) {
        switch slot.target {
        case let .family(family):
            if recording { return model.held.isEmpty ? ("Hold modifiers…", true) : (model.held.symbols + family.keysSymbol, false) }
            switch model.settings.binding(of: family) {
            case let .modifiers(m): return (m.symbols + family.keysSymbol, false)
            case .custom: return ("Custom", false)
            case .none: return ("None", true)
            }
        case .action:
            if recording { return model.held.isEmpty ? ("Recording…", true) : (model.held.symbols, false) }
            return slot.chord.map { ($0.symbol, false) } ?? ("None", true)
        }
    }
}

/// Keys shown, not edited.
struct KeyCaps: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.primary.opacity(0.06)))
    }
}

/// "Restore the default", shown only when the shortcut differs from it.
struct RestoreButton: View {
    let visible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: "arrow.uturn.backward").font(.system(size: 11, weight: .medium)).frame(width: 16, height: 16) }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Restore the default")
            .accessibilityLabel("Restore the default")
            .opacity(visible ? 1 : 0)
            .disabled(!visible)
    }
}
