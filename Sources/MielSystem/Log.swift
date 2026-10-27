import Foundation
import os

private let logger = Logger(subsystem: "my.miel.mielwm", category: "mielwm")

/// Something went wrong that the user may want to look into later. Goes to
/// stderr and the unified log: `log show --predicate 'subsystem == "my.miel.mielwm"'`.
public func log(_ message: String) {
    FileHandle.standardError.write(Data("mielwm: \(message)\n".utf8))
    logger.error("\(message, privacy: .public)")
}
