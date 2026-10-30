import AppKit
import MielCore
import SwiftUI

private let defaults = MielCore.Settings()

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
        let groups = shortcutGroups.map { group in (title: group.title, items: group.items.filter { shown($0.name, $0.detail) }) }.filter { !$0.items.isEmpty }
        let extra = others.filter { shown(actionName($0), nil) }
        let overview = overviewKeys.filter { shown($0.name, nil) }
        Form {
            Section {
                PaneHeader(pane: .keyboard) {
                    SearchField(text: $model.keyQuery, prompt: "Search shortcuts", label: "Search shortcuts")
                        .frame(width: 260)
                }
            }
            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items, id: \.name) { item in
                        switch item.target {
                        case let .action(action): ShortcutRow(action: action, name: item.name, detail: item.detail)
                        case let .family(family): FamilyRow(family: family, name: item.name, detail: item.detail)
                        }
                    }
                }
            }
            if !extra.isEmpty {
                Section("From config.json") {
                    ForEach(extra, id: \.self) { ShortcutRow(action: $0, name: actionName($0), detail: nil) }
                }
            }
            if !overview.isEmpty {
                Section {
                    ForEach(overview, id: \.keys) { key in
                        LabeledContent(key.name) { KeyCaps(text: key.keys) }
                    }
                } header: {
                    Text("In the overview")
                } footer: {
                    Text("Press ⌘/ in the overview for every key.").settingsFooter()
                }
            }
            if groups.isEmpty, extra.isEmpty, overview.isEmpty {
                Section {
                    Text("No shortcuts match “\(query)”.").font(Design.row).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            Section {
                LabeledContent {
                    Button("Restore defaults…") { model.confirmRestoreShortcuts = true }
                        .disabled(model.settings.bindings == defaults.bindings)
                } label: {
                    Text("Restore all shortcuts")
                    Text("Every action gets its default shortcut back.")
                }
            }
        }
        .confirmationDialog("Restore every shortcut?", isPresented: $model.confirmRestoreShortcuts) {
            Button("Restore defaults") { model.apply(model.settings.restoreDefaults(for: nil)) }
        } message: {
            Text("Every action gets its default shortcut back.")
        }
    }

    private var query: String { model.keyQuery.trimmingCharacters(in: .whitespaces) }

    /// Whether the search keeps a shortcut: its name or its line under it has the words.
    private func shown(_ name: String, _ detail: String?) -> Bool {
        query.isEmpty || name.localizedStandardContains(query) || (detail?.localizedStandardContains(query) ?? false)
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
                        if let detail { Text(detail).font(Design.secondary).foregroundStyle(.secondary) }
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
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(conflictText(c)).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Cancel") { model.conflict = nil }
                Button("Use here") {
                    model.conflict = nil
                    model.apply(c.changes)
                }
                .keyboardShortcut(.defaultAction)
            }
            .font(Design.secondary)
            .controlSize(.small)
        } else {
            let notes = Array(Set(chords.compactMap(systemUse))).sorted()
            ForEach(notes, id: \.self) { note in
                Label(note, systemImage: "info.circle")
                    .font(Design.secondary)
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
    @StateObject private var hover = Hover() // its own, so pointing at it redraws only it

    var body: some View {
        let recording = model.recording == slot
        let (text, dim) = label(recording: recording)
        Button { recording ? (model.recording = nil) : model.startRecording(slot) } label: {
            KeyCaps(text: text, dim: dim, hovering: hover.on, recording: recording)
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
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
            if recording { return model.held.isEmpty ? ("Type shortcut", true) : (model.held.symbols + family.keysSymbol, false) }
            switch model.settings.binding(of: family) {
            case let .modifiers(m): return (m.symbols + family.keysSymbol, false)
            case .custom: return ("Custom", false)
            case .none: return ("None", true)
            }
        case .action:
            if recording { return model.held.isEmpty ? ("Type shortcut", true) : (model.held.symbols, false) }
            return slot.chord.map { ($0.symbol, false) } ?? ("None", true)
        }
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
