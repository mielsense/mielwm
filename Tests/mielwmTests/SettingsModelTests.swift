import Foundation
import MielCore
@testable import mielwm
import Testing

// The Settings window's model on a config file of its own. No window opens.

@MainActor @Test func anEditReachesTheCanvasAtOnceAndTheFileOnFlush() throws {
    let paths = try scratchConfig()
    let model = SettingsModel(paths: paths, remembersPane: false)
    var live: MielCore.Settings?
    model.onLive = { live = $0 }
    model.set("gaps:inner_horizontal", .number(20))
    #expect(live?.gapInnerHorizontal == 20)
    #expect(loadSettings(paths).settings.gapInnerHorizontal != 20) // not written yet
    model.flush()
    #expect(loadSettings(paths).settings.gapInnerHorizontal == 20)
}

/// A rule past workspace 9 from the config file survives an edit of another rule in Settings.
@MainActor @Test func editingARuleKeepsTheOnesPastNine() throws {
    let paths = try scratchConfig(#"{"layout:workspace_rules": "com.x=12"}"#)
    let model = SettingsModel(paths: paths, remembersPane: false)
    var rules = parseWorkspaceRules(model.settings.workspaceRules)
    #expect(rules == ["com.x": 12])
    rules["com.y"] = 2
    model.set("layout:workspace_rules", .text(formatWorkspaceRules(rules)))
    model.flush()
    #expect(parseWorkspaceRules(loadSettings(paths).settings.workspaceRules) == ["com.x": 12, "com.y": 2])
}

@MainActor @Test func aValueOfTheWrongKindIsIgnored() throws {
    let paths = try scratchConfig()
    let model = SettingsModel(paths: paths, remembersPane: false)
    model.set("layout:default", .text("grid"))
    model.flush()
    #expect(!FileManager.default.fileExists(atPath: paths.config.path))
}
