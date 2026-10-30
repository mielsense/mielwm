@testable import MielCore
import Testing

// Closing and minimizing the focused window.

@Test func closeAndMinimizeCommandsRoundTrip() {
    for a: Action in [.close, .minimize] { #expect(Action(command: a.command) == a) }
    #expect(Action(command: "close now") == nil)
}

@Test func closeAndMinimizeAskSystemForTheFocusedWindow() {
    var s = focusedState()
    #expect(s.send(.action(.close)) == [.close(wid(1))])
    #expect(s.send(.action(.minimize)) == [.minimize(wid(1))])
    _ = s.send(.system(.unmanagedFocus(pid: 200))) // the desktop: nothing to close
    #expect(s.send(.action(.close)).isEmpty && s.send(.action(.minimize)).isEmpty)
    var none = makeState([])
    #expect(none.send(.action(.close)).isEmpty && none.send(.action(.minimize)).isEmpty)
}
