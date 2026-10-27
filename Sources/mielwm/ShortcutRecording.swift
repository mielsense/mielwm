import AppKit
import Carbon.HIToolbox
import MielCore
import MielSystem

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

/// Each modifier with AppKit's flag for it.
private let modifierFlags: [(Modifiers, NSEvent.ModifierFlags)] = [(.control, .control), (.option, .option), (.shift, .shift), (.command, .command)]

extension Modifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = Modifiers(modifierFlags.filter { flags.contains($0.1) }.map(\.0))
    }

    /// ⌃⌥⇧⌘, in the system's order.
    var symbols: String {
        [(Modifiers.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")].filter { contains($0.0) }.map(\.1).joined()
    }
}

extension NSEvent.ModifierFlags {
    init(_ modifiers: Modifiers) {
        self = NSEvent.ModifierFlags(modifierFlags.filter { modifiers.contains($0.0) }.map(\.1))
    }
}

extension ShortcutFamily {
    /// "1–9" or "←→↑↓": the keys after the modifiers.
    var keysSymbol: String { usesDigits ? "1–9" : "←→↑↓" }
}
