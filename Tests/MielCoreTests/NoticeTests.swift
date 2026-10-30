import CoreGraphics
import Foundation
@testable import MielCore
import Testing

// The panels over the desktop: the workspace pill, the stack strip and
// toasts outside the overview.

/// Three windows stacked on workspace 1, window 1 in front, a fourth alone on workspace 2.
func stacked(settings: Settings = testSettings(layout: .tiles)) -> CanvasState {
    var s = tilingState([snapshot(1, onBuiltIn), snapshot(2, onBuiltIn), snapshot(3, onBuiltIn)], settings: settings)
    _ = s.send(.system(.windowFocused(wid(1))))
    _ = s.send(.action(.layoutStack))
    _ = s.send(.action(.workspace(2)))
    _ = s.send(.system(.windowAppeared(snapshot(4, onBuiltIn, app: "Safari", bundle: "com.apple.Safari"))))
    _ = s.send(.action(.workspace(1)))
    _ = s.advance(2) // everything shown so far has faded, every move is confirmed or given up
    return s
}

@Test func workspaceSwitchShowsThePillThenFades() {
    var s = stacked()
    #expect(s.notices.isEmpty && !s.needsTicks)
    _ = s.send(.action(.workspace(2)))
    let pill = try! #require(s.notices.workspace)
    #expect(pill.content == WorkspaceNotice(numbers: [1, 2], current: 2, mode: .tiles, windowCount: 1))
    #expect(pill.screenID == builtIn.id)
    #expect(pill.opacity(at: s.now) == 1 && s.needsTicks)
    _ = s.advance(0.7)
    #expect(s.notices.workspace?.opacity(at: s.now) == 1) // holds 0.7 s
    _ = s.advance(0.075)
    #expect(abs((s.notices.workspace?.opacity(at: s.now) ?? 0) - 0.5) < 0.05) // then fades over 0.15 s
    _ = s.advance(0.1)
    #expect(s.notices.workspace == nil)
}

@Test func aNewSwitchResetsThePill() {
    var s = stacked()
    _ = s.send(.action(.workspace(2)))
    _ = s.advance(0.6)
    _ = s.send(.action(.workspace(1)))
    #expect(s.notices.workspace?.content.current == 1)
    #expect(s.notices.workspace?.until == s.now + 0.7)
    #expect(s.notices.workspace?.content.spoken == "Workspace 1, stack, 3 windows")
}

@Test func thePillNeedsTheSettingAndStaysOutOfTheOverview() {
    var s = stacked()
    var off = s.settings
    off.workspaceNotice = false
    _ = s.send(.setSettings(off))
    _ = s.send(.action(.workspace(2)))
    #expect(s.workspacePill == nil) // no pill on screen
    #expect(s.notices.workspace?.content.spoken == "Workspace 2, 1 window") // VoiceOver still hears it

    var t = stacked()
    _ = t.send(.action(.toggleOverview))
    _ = t.send(.action(.workspace(2)))
    _ = t.send(.action(.toggleOverview)) // landing there is not a switch you need to be told about
    #expect(t.notices.workspace == nil)
}

@Test func theStackStripFollowsTheFrontWindow() {
    var s = stacked()
    _ = s.send(.action(.workspace(2)))
    #expect(s.notices.stack == nil) // a single window: no strip
    _ = s.send(.action(.workspace(1)))
    let strip = try! #require(s.notices.stack)
    #expect(strip.content.entries.map(\.title) == ["Ghostty 1", "Ghostty 2", "Ghostty 3"])
    #expect(strip.content.position == "1 of 3" && strip.content.area == area)
    _ = s.advance(1)
    #expect(s.notices.stack == nil)
    _ = s.send(.action(.focus(.right)))
    #expect(s.notices.stack?.content.position == "2 of 3")
    _ = s.advance(1)
    _ = s.send(.system(.windowTitleChanged(wid(2), "renamed"))) // a title alone does not bring it back
    #expect(s.notices.stack == nil)
    _ = s.send(.action(.layoutStack)) // back to tiles: nothing to show
    #expect(s.notices.stack == nil)
}

@Test func toastsShowInAPanelOnlyOutsideTheOverview() {
    var s = stacked()
    _ = s.send(.action(.redo))
    #expect(s.notices.toast?.content == "Nothing to redo" && !s.notices.toastInOverview)
    #expect(s.notices.toast?.screenID == builtIn.id)
    _ = s.advance(2)
    #expect(s.notices.toast == nil)
    _ = s.send(.action(.toggleOverview))
    _ = s.send(.action(.redo))
    #expect(s.toast == "Nothing to redo" && s.notices.toastInOverview) // the overlay draws this one, not a panel
}

@Test func theSwitcherSpeaksTheSelectedApp() {
    var s = stacked()
    _ = s.send(.action(.workspace(2)))
    _ = s.send(.action(.switchWindow(forward: true)))
    _ = s.advance(1) // past the strip's delay
    #expect(s.switcherSpeech == "Ghostty")
    _ = s.send(.modifiersChanged([]))
    #expect(s.switcherSpeech == nil)
}

@Test func showWorkspaceOnSwitchIsASetting() {
    var s = Settings()
    #expect(s.workspaceNotice)
    s.set(.flag(false), forKey: "notices:workspace")
    #expect(!s.workspaceNotice)
}

// MARK: Ticks: the overlay's frames and the tick timer may rest only when nothing on screen changes

@Test func aNoticeWaitsForItsFadeThenTicksEveryFrameUntilGone() {
    var s = stacked()
    _ = s.send(.action(.workspace(2)))
    let pill = try! #require(s.notices.workspace)
    // Held: no tick every frame, one at the next deadline (the focus the switch asked for lands first).
    #expect(s.needsTicks && (s.tickDeadline ?? .infinity) <= pill.until)
    _ = s.advance(0.65)
    #expect(s.tickDeadline == pill.until)
    _ = s.advance(0.07)
    #expect(s.needsTicks && s.tickDeadline == nil) // fading: every tick changes it
    _ = s.advance(0.2)
    #expect(s.notices.workspace == nil)
}

@Test func aToastInTheOverviewKeepsItsFramesAwake() {
    var s = stacked()
    _ = s.send(.action(.toggleOverview))
    _ = s.advance(2) // the zoom has landed
    #expect(!s.needsTicks) // nothing changes: the overview may rest
    _ = s.send(.action(.redo))
    #expect(s.toast == "Nothing to redo" && s.needsTicks && s.tickDeadline == s.notices.toast?.until)
    _ = s.advance(1.9)
    #expect(s.toast != nil && s.needsTicks && s.tickDeadline == nil) // its fade
    _ = s.advance(0.1)
    #expect(s.toast == nil && !s.needsTicks)
}

@Test func theOverviewSpeaksItsSelectionAndSearch() {
    var s = makeState([snapshot(1, onBuiltIn), snapshot(2, onExternal)])
    _ = s.send(.system(.windowFocused(wid(1))))
    #expect(s.overviewSpeech == nil) // not open
    _ = s.send(.action(.toggleOverview))
    #expect(s.overviewSpeech == "Ghostty 1, Ghostty")
    _ = s.send(.action(.search("2")))
    #expect(s.overviewSpeech == "Ghostty 2, Ghostty, 1 of 1")
    _ = s.send(.action(.search("zzz")))
    #expect(s.overviewSpeech == "No windows match zzz")
}
