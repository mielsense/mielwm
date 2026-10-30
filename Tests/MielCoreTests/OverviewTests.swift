import CoreGraphics
@testable import MielCore
import Testing

// MARK: Search matcher

func candidate(_ n: UInt32, _ title: String, app: String = "Ghostty", bundle: String? = "com.mitchellh.ghostty") -> SearchCandidate {
    SearchCandidate(id: wid(n), title: title, appName: app, bundleID: bundle)
}

func ids(_ results: [SearchResult]) -> [WindowID] { results.map(\.id) }

@Test func fasFindsFastfetchNotFreeImages() throws {
    let results = searchWindows("fas", candidates: [
        candidate(1, "Free images", app: "Safari", bundle: "com.apple.Safari"), candidate(2, "fastfetch"),
    ])
    #expect(ids(results) == [wid(2)])
    #expect(try #require(results.first).titleRanges == [0 ..< 3])
}

@Test func searchIgnoresCaseAndAccents() {
    let c = [candidate(1, "Café Menu", app: "Safari", bundle: "com.apple.Safari"), candidate(2, "CAFE crawl")]
    #expect(Set(ids(searchWindows("cafe", candidates: c))) == [wid(1), wid(2)])
    #expect(Set(ids(searchWindows("CAFÉ", candidates: c))) == [wid(1), wid(2)])
    #expect(searchWindows("café", candidates: c).first { $0.id == wid(1) }?.titleRanges == [0 ..< 4])
}

@Test func everyWordMustAppearWithItsLettersTogether() {
    let c = [candidate(1, "mielwm: swift test"), candidate(2, "swift build"), candidate(3, "fastfetch")]
    #expect(ids(searchWindows("swift test", candidates: c)) == [wid(1)])
    #expect(ids(searchWindows("test swift", candidates: c)) == [wid(1)]) // words in any order
    #expect(searchWindows("fs", candidates: c).isEmpty) // f…s in fastfetch is not "fs"
    let hit = searchWindows("swift test", candidates: c)[0]
    #expect(hit.titleRanges == [8 ..< 13, 14 ..< 18])
}

@Test func searchFindsAppNamesAndCategories() {
    let c = [candidate(1, "zsh"), candidate(2, "Inbox", app: "Mail", bundle: "com.apple.mail")]
    let byApp = searchWindows("ghost", candidates: c)
    #expect(ids(byApp) == [wid(1)])
    #expect(byApp[0].titleMatches.isEmpty && byApp[0].appMatches == [0, 1, 2, 3, 4])
    #expect(ids(searchWindows("term", candidates: c)) == [wid(1)]) // every terminal
    #expect(ids(searchWindows("mail", candidates: c)) == [wid(2)])
}

@Test func searchRanksStartOfTitleFirstThenRecency() {
    let c = [candidate(1, "fastfetch"), candidate(2, "fetch logs"), candidate(3, "logs: fetch")]
    #expect(ids(searchWindows("fetch", candidates: c)) == [wid(2), wid(3), wid(1)])
    // No query: everything, most recent first.
    #expect(ids(searchWindows("", candidates: c)) == [wid(1), wid(2), wid(3)])
}

@Test func windowTheSearchStartedFromYields() {
    let c = [candidate(1, "zsh"), candidate(2, "zsh")]
    #expect(ids(searchWindows("zsh", candidates: c, returnWindow: wid(1))) == [wid(2), wid(1)])
}

// MARK: Overview keys

let notesFrame = CGRect(x: 1600, y: 700, width: 600, height: 300)

/// Three windows focused 1, 2, 3: recency is 3, 2, 1.
func threeWindows() -> CanvasState {
    var s = makeState([
        snapshot(1, onBuiltIn, title: "zsh"),
        snapshot(2, onExternal, title: "fastfetch"),
        snapshot(3, notesFrame, title: "Café notes", app: "Notes", bundle: "com.apple.Notes"),
    ])
    for n: UInt32 in [1, 2, 3] { _ = s.send(.system(.windowFocused(wid(n)))) }
    return s
}

@Test func escapeClearsTheSearchThenGoesBack() {
    var s = threeWindows()
    let camera = s.deskCamera
    _ = s.send(.action(.toggleOverview))
    _ = s.send(.text("fast"))
    #expect(s.selection == wid(2)) // the best match is selected as you type
    #expect(s.send(.key(.escape, [])).isEmpty)
    #expect(s.overview.query.isEmpty && s.isOverview)
    #expect(moves(s.send(.key(.escape, []))).isEmpty) // nothing moved
    #expect(!s.isOverview)
    #expect(s.deskCamera == camera)
}

@Test func tabWalksRecentWindowsWithoutAQuery() {
    var s = threeWindows()
    _ = s.send(.action(.toggleOverview))
    #expect(s.selection == wid(3))
    _ = s.send(.key(.tab, []))
    #expect(s.selection == wid(2))
    _ = s.send(.key(.tab, []))
    #expect(s.selection == wid(1))
    _ = s.send(.key(.tab, .shift))
    #expect(s.selection == wid(2))
}

@Test func controlDigitLandsOnThatResult() {
    var s = threeWindows()
    _ = s.send(.action(.toggleOverview))
    _ = s.send(.key(.tab, []))
    let commands = s.send(.key(.digit(3), .control))
    #expect(focuses(commands) == [wid(1)])
    #expect(!s.isOverview)
}

@Test func enterLandsOnTheBestMatchAndNothingWithoutOne() {
    var s = threeWindows()
    _ = s.send(.action(.toggleOverview))
    _ = s.send(.text("zzz"))
    #expect(s.send(.key(.enter, [])).isEmpty)
    #expect(s.isOverview)
    _ = s.send(.key(.backspace, .option)) // ⌥⌫ deletes the word
    #expect(s.overview.query.isEmpty)
    _ = s.send(.text("fas"))
    #expect(focuses(s.send(.key(.enter, []))) == [wid(2)])
}

@Test func searchActionOpensWithText() {
    var s = threeWindows()
    _ = s.send(.action(.search("notes")))
    #expect(s.isOverview && s.overview.query == "notes" && s.selection == wid(3))
}

@Test func deadKeysShowAsMarkedTextUntilTheLetter() {
    var s = threeWindows()
    _ = s.send(.action(.toggleOverview))
    _ = s.send(.markedText("´"))
    #expect(s.hud(for: builtIn).markedText == "´")
    _ = s.send(.text("é"))
    #expect(s.overview.query == "é")
    #expect(s.hud(for: builtIn).markedText.isEmpty)
}

@Test func helpSheetOpensAndEscapeClosesItFirst() {
    var s = threeWindows()
    _ = s.send(.action(.toggleOverview))
    _ = s.send(.key(.f1, []))
    #expect(s.hud(for: builtIn).mode == .help)
    _ = s.send(.key(.escape, []))
    #expect(s.hud(for: builtIn).mode == .search && s.isOverview)
}

@Test func overviewKeysAreTheMacOnesWithControlStillWorking() {
    var s = threeWindows()
    _ = s.send(.action(.toggleOverview))
    _ = s.send(.key(.character("/"), .command)) // ⌘/: the Mac's Help shortcut
    #expect(s.hud(for: builtIn).mode == .help)
    _ = s.send(.key(.character("/"), .command))
    #expect(s.hud(for: builtIn).mode == .search)
    _ = s.send(.text("fas"))
    _ = s.send(.key(.backspace, .command)) // ⌘⌫ clears the field
    #expect(s.overview.query.isEmpty)
    _ = s.send(.text("fas"))
    _ = s.send(.key(.character("u"), .command)) // readline keys stay ⌃ only
    #expect(s.overview.query == "fas")
    _ = s.send(.key(.character("u"), .control))
    #expect(s.overview.query.isEmpty)
    let zoom = s.animator.target.zoom
    _ = s.send(.key(.equals, .command))
    #expect(s.animator.target.zoom > zoom)
    _ = s.send(.key(.minus, .control)) // Phantomat's ⌃ chords still work
    #expect(abs(s.animator.target.zoom - zoom) < 0.001)
}

@Test func searchHUDRowsHighlightsAndReadouts() throws {
    var s = threeWindows()
    _ = s.send(.action(.toggleOverview))
    #expect(s.hud(for: builtIn).rows.isEmpty) // the list waits for typing or ↓
    #expect(s.hud(for: external).mode == .hidden) // the palette shows on the active screen only
    _ = s.send(.text("fas"))
    let hud = s.hud(for: builtIn)
    #expect(hud.mode == .search && hud.query == "fas")
    let row = try #require(hud.rows.first)
    #expect(row.title == "fastfetch" && row.highlights == [0 ..< 3] && row.trailing == "↩")
    #expect(row.detail.hasPrefix("Ghostty · "))
    #expect(hud.selectedRow == 0)
    // No status pill by default; the key hints always show, as keycaps.
    #expect(hud.readout.isEmpty)
    #expect(hud.hints.hasPrefix("{↩} Go  {⇥} Next"))
    var settings = s.settings
    settings.look.cornerLabels = true
    _ = s.send(.setSettings(settings))
    #expect(s.hud(for: builtIn).readout.hasSuffix("%  ·  3 windows  ·  \(builtIn.name)"))
}

@Test func hudTextIsSentenceCase() {
    var s = threeWindows()
    _ = s.send(.action(.toggleOverview))
    _ = s.send(.action(.help))
    let hud = s.hud(for: builtIn)
    let words = ([hud.placeholder, hud.footer, hud.readout, hud.hints] + hud.help.flatMap { [$0.title] + $0.entries.map(\.action) })
        .flatMap { $0.split { !$0.isLetter } }.filter { $0.count > 1 }
    #expect(!words.isEmpty)
    #expect(words.allSatisfy { $0 != $0.uppercased() }, "no word in all caps")
    let keys = hud.help.flatMap { $0.entries.map(\.keys) }
    #expect(!keys.joined().contains { "“”‘’–—".contains($0) }, "straight quotes and hyphens only")
}

@Test func helpListsEveryKeyIncludingRemaps() {
    var s = threeWindows()
    var settings = testSettings()
    settings.bindings["ctrl+opt+g"] = nil
    settings.bindings["cmd+shift+space"] = "overview"
    _ = s.send(.setSettings(settings))
    let help = s.helpSections
    #expect(help.map(\.title) == ["Search", "Mouse and trackpad", "Canvas", "Anywhere", "Workspaces"])
    let keys = Set(help.flatMap { $0.entries.map(\.keys) })
    for key in ["⌘1-9", "⇧↩", "esc", "↑ ↓ ⇥ ⇧⇥", "⌘0", "⌘F", "⌘A", "⌘Z ⌘⇧Z", "⌘,", "⌃⌥ drag", "⇧⌘Space", "⌥←→↑↓",
                "⌥⇧←→↑↓", "⌥⇥ ⌥⇧⇥", "⌥T", "⌥F", "⌥O", "⌥= ⌥-",
                "⌥/", "⌥,", "⌥.", "⌥1-9", "⌥⇧1-9", "⌃← ⌃→", "Menu bar"] {
        #expect(keys.contains(key), "missing \(key)")
    }
    #expect(!keys.contains("⌃⌥G"))
    let actions = help.flatMap { $0.entries.map(\.action) }
    #expect(Set(actions).count == actions.count, "an action listed twice")
    #expect(!actions.contains { $0.lowercased().contains("tune") || $0.lowercased().contains("tuner") })
    #expect(help.last!.entries.map(\.action) == ["Go to workspace", "Move the window there", "Previous, next workspace",
                                                 "Tiles, or flip them", "Stack", "Float, or tile again"])
    #expect(help.first { $0.title == "Anywhere" }?.entries.last?.action == "Settings…")
}

@Test func helpLeavesOutTheMinimapWhenItIsOff() {
    var s = threeWindows()
    #expect(s.helpSections[1].entries.contains { $0.keys == "Click the minimap" })
    var settings = s.settings
    settings.look.minimapEnabled = false
    _ = s.send(.setSettings(settings))
    #expect(!s.helpSections[1].entries.contains { $0.keys.contains("minimap") })
}

@Test func controlCommaClosesTheOverviewAndAsksForAppearance() {
    var s = threeWindows()
    let camera = s.deskCamera
    _ = s.send(.action(.toggleOverview))
    _ = s.send(.key(.character(","), .control))
    #expect(!s.isOverview && s.appearanceRequests == 1)
    #expect(s.deskCamera == camera) // back where it was, nothing moved
    _ = s.send(.action(.tune)) // at 100% too
    #expect(!s.isOverview && s.appearanceRequests == 2)
}

// MARK: Switcher (⌥Tab)

@Test func switcherShowsAfterADelayAndCommitsOnOptionRelease() {
    var s = threeWindows()
    #expect(s.send(.action(.switchWindow(forward: true))).isEmpty)
    #expect(s.hud(for: builtIn).mode == .hidden) // a quick flip shows nothing
    _ = s.advance(0.2)
    let hud = s.hud(for: builtIn)
    #expect(hud.mode == .switcher && hud.rows.map(\.title) == ["Café notes", "fastfetch", "zsh"] && hud.selectedRow == 1)
    _ = s.send(.action(.switchWindow(forward: true)))
    #expect(s.hud(for: builtIn).selectedRow == 2)
    _ = s.send(.action(.switchWindow(forward: false)))
    let commands = s.send(.modifiersChanged([]))
    #expect(focuses(commands) == [wid(2)])
    #expect(!s.overview.isOpen)
    #expect(s.mru.order.first == wid(2))
}

@Test func switcherEscapeCancels() {
    var s = threeWindows()
    _ = s.send(.action(.switchWindow(forward: true)))
    #expect(s.send(.key(.escape, [])).isEmpty)
    #expect(!s.overview.isOpen)
    #expect(s.send(.modifiersChanged([])).isEmpty)
    #expect(s.focused == wid(3))
}


@Test func hoverPicksOnlyMatchesWhileSearching() {
    var s = threeWindows()
    _ = s.send(.action(.toggleOverview))
    _ = s.send(.text("fast"))
    _ = s.send(.select(wid(1))) // "zsh" does not match
    #expect(s.selection == wid(2))
    _ = s.send(.key(.escape, []))
    _ = s.send(.select(wid(1)))
    #expect(s.selection == wid(1) && s.overview.selectedWindow == wid(1))
}

@Test func directionHintsReadNaturally() {
    let view = CGSize(width: 1000, height: 1000)
    #expect(directionHint(for: CGRect(x: 1400, y: 450, width: 100, height: 100), viewCenter: CGPoint(x: 500, y: 500), viewSize: view) == "→ 1 screen away")
    #expect(directionHint(for: CGRect(x: 1950, y: 450, width: 100, height: 100), viewCenter: CGPoint(x: 500, y: 500), viewSize: view) == "→ 1.5 screens away")
    #expect(directionHint(for: CGRect(x: 450, y: 2450, width: 100, height: 100), viewCenter: CGPoint(x: 500, y: 500), viewSize: view) == "↓ 2 screens away")
}

@Test func noMatchLeavesNothingLookingSelected() {
    var s = threeWindows()
    _ = s.send(.action(.toggleOverview))
    #expect(s.scene(for: builtIn).windows.contains { $0.isSelected })
    _ = s.send(.text("zzz"))
    #expect(!s.scene(for: builtIn).windows.contains { $0.isSelected })
}

@Test func theSceneSaysWhenASearchIsOn() {
    var s = makeState([snapshot(1, onBuiltIn, title: "mielwm — GitHub"), snapshot(2, onBuiltIn.offsetBy(dx: 900, dy: 0), title: "Notes")])
    _ = s.send(.action(.search("mielwm")))
    #expect(s.scene(for: builtIn).searching)
    _ = s.send(.action(.search("")))
    #expect(!s.scene(for: builtIn).searching)
}

@Test func theSearchFieldsFrameIsTheCapsuleBelowTheNotch() {
    var look = Look()
    look.hudScale = 1
    let f = PaletteMetrics.fieldFrame(look, screenSize: CGSize(width: 1512, height: 982), topInset: 38)
    #expect(f.height == look.searchHeight && f.width == look.paletteWidth && f.midX == 756)
    #expect(abs(f.minY - PaletteMetrics.top(look, screenHeight: 982, topInset: 38)) < 1e-9)
    let tall = PaletteMetrics.fieldFrame(look, screenSize: CGSize(width: 600, height: 400), topInset: 120) // a narrow display, a deep notch
    #expect(abs(tall.width - 600 * 0.94) < 1e-9 && abs(tall.minY - (120 + 12)) < 1e-9)
}

@Test func thePalettesHeightIsTheFieldTheGapAndTheCard() {
    let look = Look()
    #expect(PaletteMetrics.height(look, rows: 0, footer: false) == look.searchHeight)
    for (rows, footer) in [(1, false), (6, true)] {
        #expect(PaletteMetrics.height(look, rows: rows, footer: footer)
            == look.searchHeight + PaletteMetrics.cardGap + PaletteMetrics.cardHeight(look, rows: rows, footer: footer))
    }
    #expect(PaletteMetrics.cardHeight(look, rows: 6, footer: true) == 8 * 2 + 6 * look.rowHeight + 28)
}

@Test func hintsSplitIntoKeysAndLabels() {
    let segments = hintSegments("{⌃0} Fit all  {⎋} Back")
    #expect(segments.map(\.text) == ["⌃0", " Fit all  ", "⎋", " Back"])
    #expect(segments.map(\.isKey) == [true, false, true, false])
}
