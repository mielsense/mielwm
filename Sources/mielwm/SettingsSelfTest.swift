import AppKit
import Carbon.HIToolbox
import MielCore

/// Drives the Settings window's model and recorders the way a person would,
/// with key events posted to this process only, on a copy of the config.
/// Prints each check; exits 1 if one fails.
@MainActor
func settingsSelfTest(_ model: SettingsModel, _ window: SettingsWindow, _ paths: ConfigPaths) -> Never {
    var failed = 0
    func check(_ ok: Bool, _ what: String) {
        print(ok ? "ok    " : "FAILED", what)
        if !ok { failed += 1 }
    }
    func file() -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(contentsOf: paths.config))) as? [String: Any] ?? [:]
    }
    func key(_ code: Int, _ mods: NSEvent.ModifierFlags = [], _ chars: String = "") {
        for type in [NSEvent.EventType.flagsChanged, .keyDown] where type == .keyDown || !mods.isEmpty {
            let e = type == .flagsChanged
                ? NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: window.window.windowNumber,
                                   context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 58)
                : NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: window.window.windowNumber,
                                   context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: UInt16(code))
            NSApp.postEvent(e!, atStart: false)
            pump(0.05)
        }
    }
    var live: [MielCore.Settings] = []
    var writes = 0
    model.onLive = { live.append($0) }
    model.onWrite = { writes += 1 }
    window.show(.keyboard)
    pump(0.5)

    // The user's own config shows as it is.
    check(model.settings == loadSettings(paths).settings, "the window shows config.json as it is")

    // Accent: a swatch writes the file, the canvas gets it at once, a reload keeps it.
    model.set("navigator:accent", .text("green"))
    check(live.last?.accent == "green" && writes == 0, "accent reaches the canvas before the file")
    pump(0.4)
    check(file()["navigator:accent"] as? String == "green" && writes == 1, "accent written once, after a pause")
    check(model.settings.resolvedLook().accent == parseHexColor("#3ddc84"), "accent resolves to the preset")
    model.set("navigator:accent", .text("auto"))
    model.flush()
    check(file()["navigator:accent"] == nil, "automatic leaves the file")
    // A slider dragged: many steps, one write.
    writes = 0
    for v in stride(from: 0.1, through: 0.3, by: 0.01) { model.set("distortion:strength", .number(v)) }
    pump(0.4)
    check(writes == 1 && (file()["distortion:strength"] as? Double).map { abs($0 - 0.3) < 0.001 } == true, "a dragged slider writes once")
    // An edit to the file shows up while the window is open.
    var edited = file()
    edited["navigator:accent"] = "teal"
    try? JSONSerialization.data(withJSONObject: edited).write(to: paths.config)
    pump(1.6)
    check(model.settings.accent == "teal", "an outside edit shows up")

    // Every control's key: a value that is not the default goes to the file and comes back from it.
    let values: [(String, SettingValue)] = [
        ("animation:enabled", .flag(false)), ("blur", .flag(true)), ("canvas:grid_enabled", .flag(false)),
        // The user's file has the minimap off: on is the default, so it leaves the file.
        ("canvas:minimap_enabled", .flag(true)), ("canvas:remember_layout", .flag(false)), ("distortion:enabled", .flag(false)),
        ("navigator:labels", .flag(false)), ("navigator:pointer", .flag(false)),
        ("wallpaper", .flag(false)), ("window:shadow", .flag(false)), ("blur_strength", .number(0.4)),
        ("canvas:background_dim", .number(0.5)), ("canvas:grid_opacity", .number(0.3)), ("canvas:initial_zoom", .number(0.5)),
        ("distortion:edge_scale", .number(1.3)), ("distortion:strength", .number(0.2)), ("window:rounding", .number(20)),
        ("animation:speed", .number(2)), ("layout:default", .text("stack")), ("layout:orientation", .text("vertical")),
        ("canvas:grid_style", .text("lines")), ("layout:floating_apps", .text("com.apple.finder")),
        ("layout:workspace_rules", .text("com.apple.finder=4")), ("navigator:accent", .text("#123456")),
        ("gaps:inner_horizontal", .number(20)), ("gaps:inner_vertical", .number(22)), ("gaps:outer_left", .number(4)),
        ("gaps:outer_right", .number(6)), ("gaps:outer_bottom", .number(30)), ("gaps:outer_top", .number(2)),
        ("gaps:outer_top_external", .number(40)), ("menubar:style", .text("current")),
    ]
    for (key, value) in values { model.set(key, value) }
    model.flush()
    let reread = loadSettings(paths)
    let wrong = values.filter { reread.settings.value(forKey: $0.0) != $0.1 || model.settings.value(forKey: $0.0) != $0.1 }.map(\.0)
    check(wrong.isEmpty && reread.errors.isEmpty && values.allSatisfy { (file()[$0.0] != nil) == (MielCore.Settings().value(forKey: $0.0) != $0.1) }, "every control round-trips through the file" + (wrong.isEmpty ? "" : " \(wrong)"))
    for (key, _) in values { model.set(key, MielCore.Settings().value(forKey: key)!) }
    model.flush()
    check(values.allSatisfy { file()[$0.0] == nil }, "every control back at its default leaves the file")

    // A shortcut: click, press keys.
    model.startRecording(ShortcutSlot(target: .action(.pin), chord: KeyChord("opt+o")))
    key(kVK_ANSI_P, [.control, .option], "p")
    check(model.recording == nil && model.settings.chords(for: .pin) == [KeyChord("ctrl+opt+p")!], "⌃⌥P replaces ⌥O for pin")
    check(file()["keys:opt+o"] as? String == "none" && file()["keys:ctrl+opt+p"] as? String == "pin", "written as none + pin")
    model.startRecording(ShortcutSlot(target: .action(.pin), chord: KeyChord("ctrl+opt+p")))
    key(kVK_ANSI_L, [], "l")
    check(model.recording != nil, "a plain letter is refused, still recording")
    key(kVK_ANSI_Q, [.command], "q")
    check(model.recording != nil, "⌘Q is refused")
    key(kVK_Escape)
    check(model.recording == nil && model.settings.chords(for: .pin) == [KeyChord("ctrl+opt+p")!], "Esc cancels")
    model.startRecording(ShortcutSlot(target: .action(.pin), chord: KeyChord("ctrl+opt+p")))
    key(kVK_Delete)
    check(model.settings.chords(for: .pin).isEmpty, "Delete clears")
    model.startRecording(ShortcutSlot(target: .action(.pin), chord: nil))
    key(kVK_ANSI_O, [.option], "o")
    check(model.settings.chords(for: .pin) == [KeyChord("opt+o")!] && file()["keys:opt+o"] == nil, "the default again leaves the file")

    // A family: modifiers, then any of its keys.
    model.startRecording(ShortcutSlot(target: .family(.workspace), chord: nil))
    key(kVK_ANSI_5, [.control, .option], "5")
    check(model.settings.binding(of: .workspace) == .modifiers([.control, .option]), "⌃⌥ + a digit sets all nine")
    model.startRecording(ShortcutSlot(target: .family(.workspace), chord: nil))
    key(kVK_ANSI_5, [.shift], "%")
    check(model.recording != nil, "⇧ alone is refused")
    key(kVK_ANSI_A, [.option], "a")
    check(model.recording != nil, "a key outside the family is refused")
    key(kVK_Return, [.option])
    check(model.recording == nil && model.settings.binding(of: .workspace) == .modifiers(.option), "⌥↩ confirms ⌥ (back to the default)")
    // Taking keys another action has: asks first.
    model.startRecording(ShortcutSlot(target: .family(.nudge), chord: nil))
    key(kVK_LeftArrow, [.control])
    check(model.conflict?.others.count == 2 && model.settings.binding(of: .nudge) == .modifiers([.option, .shift]), "⌃ arrows ask about the workspace keys")
    if let c = model.conflict {
        model.conflict = nil
        model.apply(c.changes)
    }
    check(model.settings.binding(of: .nudge) == .modifiers(.control) && model.settings.chords(for: .workspaceStep(forward: true)).isEmpty,
          "Use here moves them")
    check(loadSettings(paths).errors.isEmpty, "the file still loads cleanly")
    model.apply(model.settings.restoreDefaults(for: nil))
    check(model.settings.bindings == MielCore.Settings().bindings, "Restore defaults")

    // The command-line tool, into a scratch ~/.local/bin.
    let link = paths.config.deletingLastPathComponent().appendingPathComponent("bin/\(CLITool.name)")
    check(CLITool.status(link: link) == .missing, "tool: missing")
    check((try? CLITool.install(link: link)).map { if case .installed = $0 { true } else { false } } == true, "tool: installed")
    check(CLITool.remove(link: link) == .missing, "tool: removed")
    try? Data().write(to: link)
    check(CLITool.status(link: link) != .missing && CLITool.remove(link: link) != .missing, "tool: someone else's file is left alone")

    print(failed == 0 ? "all passed" : "\(failed) failed")
    exit(failed == 0 ? 0 : 1)
}
