import Foundation
import MielCore
@testable import mielwm
import Testing

// What the menu warns about, on a test copy's own config file. Nothing starts.

@MainActor @Test func thePermissionWarningOutlastsAConfigReload() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mielwm-app-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("config.json")
    try Data("{ not json".utf8).write(to: file)

    let controller = Controller(mode: .manageOnly(getpid()), paths: ConfigPaths(config: file))
    controller.permissionProblems = [Controller.shortcutsNeedAccessibility]
    #expect(controller.problems.count == 2)

    try Data("{}".utf8).write(to: file)
    controller.reloadConfig()
    #expect(controller.problems == [Controller.shortcutsNeedAccessibility])
}
