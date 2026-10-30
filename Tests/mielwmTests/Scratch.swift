import Foundation
import MielCore

/// A config file of its own in a new folder, removed when the run ends.
func scratchConfig(_ text: String? = nil) throws -> ConfigPaths {
    let dir = scratchRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let paths = ConfigPaths(config: dir.appendingPathComponent("config.json"))
    if let text { try Data(text.utf8).write(to: paths.config) }
    return paths
}

private let scratchRoot: URL = {
    atexit { try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("mielwm-app-tests-\(getpid())")) }
    return FileManager.default.temporaryDirectory.appendingPathComponent("mielwm-app-tests-\(getpid())", isDirectory: true)
}()
