import Foundation
@testable import MielCore
import Testing

@Test func importsTheRealAeroSpaceConfig() {
    let found = AeroSpaceImport(toml: realAeroSpaceConfig)
    #expect(found.gaps == [
        "gaps:inner_horizontal": 8, "gaps:inner_vertical": 8, "gaps:outer_left": 12, "gaps:outer_right": 12,
        "gaps:outer_bottom": 12, "gaps:outer_top": 12, "gaps:outer_top_external": 54,
    ])
    #expect(found.layout == .tiles && found.orientation == .auto)
    #expect(found.workspaceRules == [
        "dev.warp.Warp-Stable": 5, "com.spotify.client": 2, "com.hnc.Discord": 1,
        "company.thebrowser.Browser": 3, "dev.zed.Zed": 4, "co.routine.desktop": 9,
    ])
    #expect(found.floatingApps.isEmpty)
    // Main-mode keys only (service mode's alt-left is join-with, not focus).
    #expect(found.bindings["opt+left"] == "focus left" && found.bindings["opt+shift+down"] == "nudge down")
    #expect(found.bindings["opt+slash"] == "layout tiles" && found.bindings["opt+comma"] == "layout stack")
    #expect(found.bindings["opt+minus"] == "shrink" && found.bindings["opt+equal"] == "grow")
    #expect(found.bindings["opt+3"] == "workspace 3" && found.bindings["opt+shift+7"] == "move-to-workspace 7")
    #expect(found.bindings["ctrl+right"] == "workspace next" && found.bindings["opt+f"] == "fullscreen")
    #expect(found.bindings["opt+tab"] == nil && found.bindings["opt+shift+tab"] == nil && found.bindings["opt+semicolon"] == nil)
    #expect(found.bindings.count == 4 + 4 + 2 + 2 + 9 + 9 + 2 + 1)
    // The defaults already are AeroSpace's: importing keys changes nothing.
    #expect(found.changes(onto: Settings(), keys: true).filter { $0.key.hasPrefix("keys:") }.allSatisfy { $0.value == nil })
}

@Test func importChangesMergeWithWhatIsSet() {
    var s = Settings()
    s.workspaceRules = "com.spotify.client=7,org.other=2"
    s.floatingApps = "com.apple.calculator"
    var found = AeroSpaceImport(toml: realAeroSpaceConfig)
    found.floatingApps = ["com.apple.calculator", "com.new.app"]
    let changes = found.changes(onto: s, keys: false)
    #expect(changes["gaps:outer_top_external"] == .some(nil)) // 54 is already the default
    #expect(changes["gaps:inner_horizontal"] == .some(nil))
    #expect(changes["layout:floating_apps"] == .some(.text("com.apple.calculator,com.new.app")))
    let rules = changes["layout:workspace_rules"].flatMap { $0 }
    guard case let .text(text)? = rules else { Issue.record("no rules"); return }
    #expect(parseWorkspaceRules(text)["com.spotify.client"] == 2 && parseWorkspaceRules(text)["org.other"] == 2)
    #expect(!changes.keys.contains { $0.hasPrefix("keys:") })
}

@Test func importReadsOtherForms() {
    let found = AeroSpaceImport(toml: """
    gaps.inner.horizontal = 4 # flat
    gaps.outer.top = [{ monitor.main = 16 }, { monitor."Built-in Retina Display" = 30 }, 40]
    default-root-container-layout = "accordion"
    default-root-container-orientation = 'vertical'
    after-startup-command = [
        'exec-and-forget borders', # a comment inside
    ]
    garbage line without equals
    [[on-window-detected]]
    if.app-id = "com.apple.finder"
    run = ['layout floating']
    [[on-window-detected]]
    if.app-id = "com.x"
    run = ["move-node-to-workspace 6", "layout floating"]
    [mode.main.binding]
    cmd-alt-backtick = ['move-node-to-workspace 2', 'workspace 2']
    alt-shift-leftSquareBracket = "resize smart -10"
    alt-enter = '''exec-and-forget open -a Terminal'''
    alt-h = 'focus --boundaries all-monitors-outer-frame left'
    """)
    #expect(found.gaps == ["gaps:inner_horizontal": 4, "gaps:outer_top": 30, "gaps:outer_top_external": 40])
    #expect(found.layout == .stack && found.orientation == .vertical)
    #expect(found.floatingApps == ["com.apple.finder", "com.x"] && found.workspaceRules == ["com.x": 6])
    #expect(found.bindings == ["opt+cmd+grave": "move-to-workspace 2", "opt+shift+leftbracket": "resize smart -10"])
    #expect(found.summary().count == 5)
    let summary = found.summary { $0 == "com.x" ? "X" : $0 }
    #expect(summary.contains("Workspace rules: X → 6.") && summary.contains("New windows: a stack, above each other orientation."))
    #expect(summary.first == "Gaps: 4 pt between windows side by side, 30 pt at the top, 40 pt at the top of other displays.")
}

@Test func emptyOrJunkImportsNothing() {
    #expect(AeroSpaceImport(toml: "").isEmpty)
    #expect(AeroSpaceImport(toml: "[[[\n= = =\n'unterminated").isEmpty)
}

@Test func importReadsTheNewCommandsAndRules() {
    let found = AeroSpaceImport(toml: """
    [[on-window-detected]]
    if.app-id = 'org.mozilla.firefox'
    if.window-title-regex-substring = 'Picture-in-Picture'
    run = 'layout floating'
    [[on-window-detected]]
    if.window-title-regex-substring = '(['
    run = 'layout floating'
    [[on-window-detected]]
    if.app-name-regex-substring = 'zoom'
    run = ['move-node-to-workspace 3']
    [[on-window-detected]]
    if.window-title-regex-substring = 'nothing to do'
    run = 'exec-and-forget true'
    [mode.main.binding]
    alt-b = 'workspace-back-and-forth'
    alt-tab = 'workspace-back-and-forth'
    alt-1 = 'workspace --auto-back-and-forth 1'
    alt-w = 'close'
    alt-m = 'macos-native-minimize'
    alt-shift-minus = 'resize width -100'
    alt-shift-equal = 'resize smart +50'
    alt-r = 'resize smart 900'
    """)
    #expect(found.windowRules == [
        "aerospace-1": WindowRule(appID: "org.mozilla.firefox", title: "Picture-in-Picture", floating: true),
        "aerospace-3": WindowRule(app: "zoom", workspace: 3), // numbered by block; the second's pattern doesn't compile
    ])
    #expect(found.workspaceRules.isEmpty && found.floatingApps.isEmpty)
    #expect(found.bindings == [
        "opt+b": "workspace-back-and-forth", "opt+1": "workspace 1", "opt+w": "close", "opt+m": "minimize",
        "opt+shift+minus": "resize width -100", "opt+shift+equal": "grow",
    ]) // ⌥Tab stays the window switcher; a size to set has no mielwm command
    #expect(found.autoBackAndForth)
    var before = Settings()
    before.windowRules = ["aerospace-7": WindowRule(title: "gone from AeroSpace", floating: true), "mine": WindowRule(app: "x", floating: true)]
    let changes = found.changes(onto: before, keys: false)
    #expect(changes["rules:aerospace-1:title"] == .some(.text("Picture-in-Picture")))
    #expect(changes["rules:aerospace-1:floating"] == .some(.flag(true)))
    #expect(changes["rules:aerospace-1:workspace"] == .some(nil)) // cleared, in case an earlier import set it
    #expect(changes["rules:aerospace-3:workspace"] == .some(.number(3)))
    #expect(changes["rules:aerospace-7:title"] == .some(nil) && changes["rules:aerospace-7:floating"] == .some(nil)) // an old import's rule goes
    #expect(!changes.keys.contains { $0.hasPrefix("rules:mine:") }) // the user's own stay
    #expect(changes["layout:auto_back_and_forth"] == .some(.flag(true)))
    #expect(found.summary().contains("2 window rules by app name or title."))
}
