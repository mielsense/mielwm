@testable import MielCore
import Testing

// workspace-back-and-forth, and the key of the current workspace going back.

@Test func backAndForthGoesToTheWorkspaceBefore() {
    var s = twoTiles()
    #expect(s.send(.action(.workspaceBackAndForth)).isEmpty) // nowhere to go back to yet
    #expect(s.currentWorkspace == 1)
    _ = s.send(.action(.workspace(3)))
    #expect(s.previousWorkspace == 1)
    _ = s.send(.action(.workspaceBackAndForth))
    #expect(s.currentWorkspace == 1 && s.focused == wid(1))
    _ = s.send(.action(.workspaceBackAndForth))
    #expect(s.currentWorkspace == 3)
}

@Test func theKeyOfTheCurrentWorkspaceGoesBackOnlyWhenAsked() {
    var s = twoTiles()
    _ = s.send(.action(.workspace(2)))
    #expect(s.boundAction(.workspace(2)) == .workspace(2)) // off by default: it stays
    s.settings.autoBackAndForth = true
    #expect(s.boundAction(.workspace(2)) == .workspace(1))
    #expect(s.boundAction(.workspace(3)) == .workspace(3)) // another workspace goes there as usual
    #expect(s.boundAction(.fill) == .fill)
    _ = s.send(.action(.workspace(2))) // the command line and Barik stay put
    #expect(s.currentWorkspace == 2)
}
