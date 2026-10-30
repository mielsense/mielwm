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
