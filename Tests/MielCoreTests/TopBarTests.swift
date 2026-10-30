import CoreGraphics
import Foundation
@testable import MielCore
import Testing

// The top gap: a status bar found along a display's top edge, and the
// three ways the top gap uses it.

@Test func aBarAlongTheTopIsFound() {
    // Pinned to the top of a display with the menu bar hidden.
    let barik = (owner: "Barik", frame: CGRect(x: 1512, y: 0, width: 1920, height: 40))
    #expect(topBar(among: [barik], on: external) == TopBar(owner: "Barik", height: 40))
    // Just under an always-shown menu bar.
    let under = (owner: "SketchyBar", frame: CGRect(x: 0, y: 38, width: 1512, height: 32))
    #expect(topBar(among: [under], on: builtIn) == TopBar(owner: "SketchyBar", height: 32))
    // At the top of the display, partly behind the menu bar: only what shows below it counts.
    let behind = (owner: "Barik", frame: CGRect(x: 0, y: 0, width: 1512, height: 55))
    #expect(topBar(among: [behind], on: builtIn)?.height == 17)
    // The tallest of two wins.
    #expect(topBar(among: [under, behind], on: builtIn)?.owner == "SketchyBar")
}

@Test func otherWindowsAreNotBars() {
    let cases: [(String, CGRect)] = [
        ("narrow", CGRect(x: 1512, y: 0, width: 1000, height: 40)), // under 80% of the width
        ("short", CGRect(x: 1512, y: 0, width: 1920, height: 12)),
        ("tall", CGRect(x: 1512, y: 0, width: 1920, height: 300)),
        ("lower", CGRect(x: 1512, y: 200, width: 1920, height: 40)), // not at the top
        ("elsewhere", CGRect(x: 0, y: 38, width: 1512, height: 40)), // the other display
    ]
    for (name, frame) in cases { #expect(topBar(among: [(name, frame)], on: external) == nil, "\(name)") }
    // Hidden behind an always-shown menu bar: nothing to make room for.
    #expect(topBar(among: [("menu", CGRect(x: 0, y: 0, width: 1512, height: 24))], on: builtIn) == nil)
}

@Test func theTopGapFollowsItsMode() {
    var withBar = external
    withBar.topBar = TopBar(owner: "Barik", height: 40)
    var s = Settings()
    #expect(s.topGapMode == .auto)
    #expect(s.topGap(on: external) == 12 && s.topGap(on: withBar) == 52 && s.topGap(on: builtIn) == 12)
    s.topGapMode = .same
    #expect(s.topGap(on: withBar) == 12)
    s.topGapMode = .custom
    #expect(s.topGap(on: withBar) == 54 && s.topGap(on: builtIn) == 12) // the built-in display keeps the top gap
    #expect(s.tileArea(on: withBar) == CGRect(x: 1524, y: 54, width: 1896, height: 1014))
}

@Test func outerTopExternalTakesAModeOrANumber() {
    // No value: Automatic. A number, as configs and the AeroSpace import write it: Custom.
    #expect(parseSettings(config: json("{}")).settings.topGapMode == .auto)
    let number = parseSettings(config: json(#"{"gaps": {"outer_top_external": 40}}"#))
    #expect(number.errors.isEmpty && number.settings.topGapMode == .custom && number.settings.gapOuterTopExternal == 40)
    #expect(parseSettings(config: json(#"{"gaps:outer_top_external": "same"}"#)).settings.topGapMode == .same)
    #expect(parseSettings(config: json(#"{"gaps:outer_top_external": "Auto"}"#)).settings.topGapMode == .auto)
    #expect(parseSettings(config: json(#"{"gaps:outer_top_external": "custom"}"#)).errors.count == 1) // Custom is a number
    #expect(parseSettings(config: json(#"{"gaps:outer_top_external": true}"#)).errors.count == 1)
    // Automatic is the default and leaves the file; any number is written, even the old default.
    #expect(Settings.entry("gaps:outer_top_external", .text("auto")) == nil)
    #expect(Settings.entry("gaps:outer_top_external", .number(54)) == .number(54))
    #expect(Settings.entry("gaps:outer_top_external", .text("same")) == .text("same"))
    #expect(Settings().value(forKey: "gaps:outer_top_external") == .text("auto"))
}

@Test func aBarComingOrGoingRetilesItsDisplay() {
    var s = tilingState([snapshot(1, onBuiltIn)])
    let before = s.canvasFrame(1)
    var withBar = builtIn
    withBar.topBar = TopBar(owner: "SketchyBar", height: 30)
    let commands = s.send(.system(.screensChanged([withBar, external])))
    #expect(s.canvasFrame(1)?.minY == before.map { $0.minY + 30 })
    #expect(!commands.isEmpty)
    _ = s.send(.system(.screensChanged([builtIn, external])))
    #expect(s.canvasFrame(1) == before)
}

@Test func bariksBarHeightComesFromItsConfig() {
    #expect(BarikConfig.barHeight("", menuBar: 24) == 55)
    #expect(BarikConfig.barHeight("[experimental.foreground]\nheight = 40\n", menuBar: 24) == 40)
    #expect(BarikConfig.barHeight("[experimental.foreground]\nheight = \"menu-bar\"\n", menuBar: 24) == 24)
    #expect(BarikConfig.barHeight("[experimental.foreground]\nheight = \"default\"\n", menuBar: 24) == 55)
}

@Test func menuBarStyleReadsTheOldSwitch() {
    #expect(Settings().menuBarStyle == .all)
    #expect(Settings.entry("menubar:style", .text("all")) == nil)
    let off = parseSettings(config: json(#"{"menubar": {"workspaces": false}}"#))
    #expect(off.errors.isEmpty && off.settings.menuBarStyle == .icon)
    #expect(parseSettings(config: json(#"{"menubar:workspaces": true}"#)).settings.menuBarStyle == .all)
    let both = parseSettings(config: json(#"{"menubar:style": "current", "menubar:workspaces": true}"#))
    #expect(both.errors.isEmpty && both.settings.menuBarStyle == .current)
    #expect(parseSettings(config: json(#"{"menubar:style": "numbers"}"#)).errors.count == 1)
}
