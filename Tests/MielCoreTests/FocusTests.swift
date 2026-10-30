@testable import MielCore
import Testing

// Which window has focus, as window keys see it.

@Test func focusOnSomethingUnmanagedLeavesNoWindowForTheKeys() {
    var s = focusedState()
    _ = s.send(.system(.unmanagedFocus(pid: 200))) // the desktop, a sheet, or an app mielwm leaves alone
    #expect(s.focused == nil)
    #expect(s.send(.action(.fill)).isEmpty) // not the window that had focus before
    _ = s.send(.system(.windowFocused(wid(1))))
    #expect(s.focused == wid(1))
}

@Test func focusOnMielwmOrRightAfterAskingForAWindowIsKept() {
    var s = focusedState()
    _ = s.send(.system(.unmanagedFocus(pid: 1))) // mielwm's own windows: the overview, Settings
    #expect(s.focused == wid(1))
    _ = s.send(.action(.toggleOverview))
    _ = s.send(.system(.unmanagedFocus(pid: 200)))
    #expect(s.focused == wid(1) && s.selection == wid(1))
}

@Test func focusOnADialogMielwmDoesNotManageLeavesNoWindowForTheKeys() {
    var s = focusedState()
    var dialog = snapshot(2, onBuiltIn)
    dialog.isStandard = false // System reports it; Core leaves it alone
    _ = s.send(.system(.windowAppeared(dialog)))
    _ = s.send(.system(.windowFocused(wid(2))))
    #expect(s.focused == nil)
    #expect(s.send(.action(.fill)).isEmpty)
}

@Test func focusOnAHiddenOrMinimizedWindowLandsOnceItShows() {
    let other = wid(2, pid: 200)
    var s = focusedState()
    _ = s.send(.system(.windowAppeared(snapshot(2, onBuiltIn, pid: 200))))
    _ = s.send(.system(.appHidden(pid: 200, true)))
    _ = s.send(.system(.windowFocused(other))) // ⌘Tab to the hidden app: focus is reported before it unhides
    #expect(s.focused == nil)
    _ = s.send(.system(.appHidden(pid: 200, false)))
    #expect(s.focused == other)
    _ = s.send(.system(.windowMinimized(other, true))) // mielwm focuses the workspace's last window meanwhile
    _ = s.advance(1) // the click in the Dock comes after that focus has landed
    _ = s.send(.system(.windowFocused(other))) // a click on it in the Dock
    _ = s.send(.system(.windowMinimized(other, false)))
    #expect(s.focused == other)
    _ = s.send(.system(.windowMinimized(other, true)))
    _ = s.send(.system(.windowFocused(other)))
    _ = s.send(.system(.windowFocused(wid(1)))) // focus moved on before it came back
    _ = s.send(.system(.windowMinimized(other, false)))
    #expect(s.focused == wid(1))
}

@Test func focusThatChangesWhileAFocusWeAskedForLandsIsAppliedAfterwards() {
    var s = twoWindows()
    _ = s.send(.action(.focus(.right))) // mielwm focuses window 2 and waits a moment for it to land
    _ = s.send(.system(.unmanagedFocus(pid: 300))) // the user clicks the desktop right away
    #expect(s.focused == wid(2))
    _ = s.advance(1)
    #expect(s.focused == nil)
    #expect(s.send(.action(.close)).isEmpty)

    s = twoWindows()
    _ = s.send(.action(.focus(.right)))
    _ = s.send(.system(.windowFocused(wid(1)))) // a stray report from before
    _ = s.send(.system(.windowFocused(wid(2)))) // then the focus we asked for lands
    _ = s.advance(1)
    #expect(s.focused == wid(2))
}

@Test func aFocusAfterOursLandedIsAppliedOnceTheWaitEnds() {
    var s = twoWindows()
    _ = s.send(.action(.focus(.right)))
    _ = s.send(.system(.windowFocused(wid(2)))) // ours lands
    _ = s.send(.system(.windowFocused(wid(1)))) // then the user clicks window 1
    _ = s.advance(1)
    #expect(s.focused == wid(1))
}

@Test func ourFocusReportedBeforeTheWindowShowsLandsWhenItDoes() {
    var s = twoWindows()
    _ = s.send(.action(.focus(.right))) // mielwm focuses window 2
    _ = s.send(.system(.windowMinimized(wid(2), true)))
    _ = s.send(.system(.windowFocused(wid(2)))) // reported in, but not shown yet
    _ = s.advance(1) // the unminimize takes longer than the wait
    _ = s.send(.system(.windowMinimized(wid(2), false)))
    #expect(s.focused == wid(2))
}
