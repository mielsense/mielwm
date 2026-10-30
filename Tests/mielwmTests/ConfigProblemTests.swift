import Foundation
import MielCore
@testable import mielwm
import Testing

// What the menu warns about, on a test copy's own config file. Nothing starts.

@MainActor @Test func thePermissionWarningOutlastsAConfigReload() throws {
    let paths = try scratchConfig("{ not json")
    let controller = Controller(mode: .manageOnly(getpid()), paths: paths)
    controller.permissionProblems = [Controller.shortcutsNeedAccessibility]
    #expect(controller.problems.count == 2)

    try Data("{}".utf8).write(to: paths.config)
    controller.reloadConfig()
    #expect(controller.problems == [Controller.shortcutsNeedAccessibility])
}
