import Foundation
@testable import MielIPC
import Testing

// The socket the app, the `mielwm` command and the `aerospace` command share,
// each test on a socket of its own.

private func socketPath(_ name: String) -> String { "/tmp/mielwm-\(getpid())-\(name).sock" }

@Test(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "the server answers on the main queue, which CI runners keep busy")) @MainActor func ipcRoundTrip() async throws {
    let path = socketPath("rt")
    let server = try IPCServer(path: path) { args, reply in
        reply(try! JSONEncoder().encode(["echo": args]))
    }
    defer { server.stop() }
    // The server replies on the main queue, which other tests keep busy on slow CI runners.
    let response = try await Task.detached { try IPCClient.send(["focus", "left"], path: path, timeout: 30) }.value
    #expect(try JSONDecoder().decode([String: [String]].self, from: response) == ["echo": ["focus", "left"]])
    #expect(throws: IPCError.alreadyRunning) { try IPCServer(path: path) { _, _ in } }
}

@Test @MainActor func ipcRejectsMalformedRequests() async throws {
    let path = socketPath("bad")
    let server = try IPCServer(path: path) { _, reply in reply(Data("{}".utf8)) }
    defer { server.stop() }
    let response = try await Task.detached { () throws -> Data? in
        let fd = try connectSocket(path)
        defer { close(fd) }
        writeLine(fd, Data(#"{"not":"an array"}"#.utf8))
        return readLine(fd)
    }.value
    #expect(response == Data(#"{"error":"bad request"}"#.utf8))
}

@Test func ipcReplacesAStaleSocketAndReportsNoServer() throws {
    let path = socketPath("stale")
    FileManager.default.createFile(atPath: path, contents: Data())
    let server = try IPCServer(path: path) { _, _ in }
    server.stop()
    #expect(!FileManager.default.fileExists(atPath: path))
    #expect(throws: IPCError.notRunning) { try IPCClient.send(["state"], path: path) }
}

/// Runs the built `aerospace` command against `path` and returns what it printed.
private func aerospace(_ args: [String], socket path: String) async throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".build/debug/mielwm-aerospace")
    process.arguments = args
    process.environment = ["MIELWM_SOCKET": path]
    let out = Pipe()
    process.standardOutput = out
    try process.run()
    return try await Task.detached {
        let data = try out.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }.value
}

// The command speaks the socket protocol without Foundation, so check it against the real server.
@Test(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "the command waits 0.3 s, and CI runners keep the main queue busy"))
@MainActor func aerospaceCommandTalksToTheServer() async throws {
    let path = socketPath("aero")
    let odd = "quote \" backslash \\ tab \t newline \n é 🙂"
    let server = try IPCServer(path: path) { args, reply in
        switch args.dropFirst().first {
        case "echo": reply(try! JSONEncoder().encode(Array(args.dropFirst(2))))
        case "list-nothing": reply(Data(#"{"error":"unknown command"}"#.utf8))
        default: reply(Data())
        }
    }
    #expect(try await aerospace(["echo", odd, ""], socket: path) == #"["quote \" backslash \\ tab \t newline \n é 🙂",""]"# + "\n")
    #expect(try await aerospace(["focus", "left"], socket: path) == "") // an action prints nothing
    #expect(try await aerospace(["list-nothing"], socket: path) == "[]\n") // a command mielwm doesn't know
    server.stop()
    #expect(try await aerospace(["list-workspaces", "--all"], socket: path) == "[]\n") // no mielwm
    #expect(try await aerospace(["workspace", "2"], socket: path) == "")
}

@Test func aSocketPathTooLongForUnixSocketsIsRefused() {
    let path = "/tmp/" + String(repeating: "x", count: 200) + ".sock"
    #expect(throws: IPCError.pathTooLong) { try IPCServer(path: path) { _, _ in } }
    #expect(throws: IPCError.pathTooLong) { try IPCClient.send(["state"], path: path) }
}

@Test @MainActor func onlyTheFirstReplyIsSent() async throws {
    let path = socketPath("twice")
    let server = try IPCServer(path: path) { _, reply in
        reply(Data(#"{"first":true}"#.utf8))
        reply(Data(#"{"second":true}"#.utf8)) // its descriptor may already belong to someone else
    }
    defer { server.stop() }
    let response = try await Task.detached { try IPCClient.send(["state"], path: path, timeout: 30) }.value
    #expect(response == Data(#"{"first":true}"#.utf8))
}

/// The app answers an action from the `aerospace` command with nothing, and the command prints nothing.
@Test(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "the server answers on the main queue, which CI runners keep busy")) @MainActor func anEmptyReplyArrivesEmpty() async throws {
    let path = socketPath("empty")
    let server = try IPCServer(path: path) { _, reply in reply(Data()) }
    defer { server.stop() }
    let response = try await Task.detached { try IPCClient.send(["aerospace", "workspace", "2"], path: path, timeout: 30) }.value
    #expect(response.isEmpty)
}
