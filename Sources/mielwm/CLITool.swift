import Foundation

/// The `mielwm` binary linked into ~/.local/bin.
enum CLITool {
    enum Status: Equatable { case missing, installed(String), taken(String) }

    static var name: String { Bundle.main.executableURL?.lastPathComponent ?? "mielwm" }
    static func link(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".local/bin").appendingPathComponent(name)
    }

    static var target: URL? { Bundle.main.executableURL?.resolvingSymlinksInPath() }

    static func status(link: URL = link()) -> Status {
        let shown = (link.path as NSString).abbreviatingWithTildeInPath
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else {
            return FileManager.default.fileExists(atPath: link.path) ? .taken(shown) : .missing
        }
        return URL(fileURLWithPath: dest).resolvingSymlinksInPath() == target ? .installed(shown) : .taken(shown)
    }

    static func install(link: URL = link()) throws -> Status {
        guard let target else { return .missing }
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil || FileManager.default.fileExists(atPath: link.path) {
            try FileManager.default.removeItem(at: link)
        }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        return status(link: link)
    }

    static func remove(link: URL = link()) -> Status {
        if case .installed = status(link: link) { try? FileManager.default.removeItem(at: link) }
        return status(link: link)
    }
}
