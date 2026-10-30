import Foundation
@testable import MielCore
import Testing

// How the HUD lays out: the ⌥Tab strip's window onto many apps, and the shortcuts sheet.

@Test func theSwitcherStripCentresTheSelectionAndStopsAtTheEnds() {
    #expect(PaletteMetrics.switcherWindow(count: 3, selected: 1, maxTiles: 8) == (0, 3, 1)) // all fit
    #expect(PaletteMetrics.switcherWindow(count: 20, selected: 10, maxTiles: 5) == (8, 5, 10)) // centred
    #expect(PaletteMetrics.switcherWindow(count: 20, selected: 0, maxTiles: 5) == (0, 5, 0))
    #expect(PaletteMetrics.switcherWindow(count: 20, selected: 19, maxTiles: 5) == (15, 5, 19))
    #expect(PaletteMetrics.switcherWindow(count: 4, selected: nil, maxTiles: 0) == (0, 1, 0)) // at least one tile
    #expect(PaletteMetrics.switcherWindow(count: 4, selected: 9, maxTiles: 8) == (0, 4, 3)) // clamped
}

@Test func helpSectionsSplitIntoColumnsOfAboutEqualHeight() {
    func section(_ title: String, _ rows: Int) -> HelpSection {
        HelpSection(title: title, entries: (0 ..< rows).map { (keys: "⌘\($0)", action: "Row \($0)") })
    }
    let sections = [section("A", 6), section("B", 6), section("C", 6), section("D", 1), section("E", 1)]
    let columns = HelpSection.columns(sections, count: 3)
    #expect(columns.map { $0.map(\.title) } == [["A"], ["B"], ["C", "D", "E"]])
    #expect(HelpSection.columns(sections, count: 1).map(\.count) == [5])
    #expect(HelpSection.columns([], count: 3).map(\.count) == [0])
}

@Test func helpKeysAreCapsAndWordsStayText() {
    let tokens = HelpSection.keyTokens("Pinch or ⌘ scroll").map { "\($0.isKey ? "[" : "")\($0.text)\($0.isKey ? "]" : "")" }
    #expect(tokens == ["Pinch or", "[⌘]", "scroll"])
    #expect(HelpSection.keyTokens("esc").map(\.isKey) == [true])
    #expect(HelpSection.keyTokens("Click the minimap").map(\.text) == ["Click the minimap"])
}
