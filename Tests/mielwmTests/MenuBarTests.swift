import MielCore
@testable import mielwm
import Testing

// The menu bar item's numbers, by menubar:style.

private let status = Controller.WorkspaceStatus(numbers: [1, 2, 5], current: 2, mode: .tiles)

@MainActor @Test func allWorkspacesShowsEveryNumberWithWindows() {
    #expect(AppDelegate.shownNumbers(.all, status) == [1, 2, 5])
}

@MainActor @Test func currentShowsOnlyTheCurrentWorkspace() {
    #expect(AppDelegate.shownNumbers(.current, status) == [2])
    #expect(AppDelegate.shownNumbers(.current, Controller.WorkspaceStatus(numbers: [1], current: nil)) == nil)
}

@MainActor @Test func iconShowsNoNumbers() {
    #expect(AppDelegate.shownNumbers(.icon, status) == nil)
}
