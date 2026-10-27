import Foundation
import os

/// `mielwm <action>` and `mielwm state` reach the running app over a
/// Unix-domain socket. A request is one line holding a JSON array of
/// strings (the CLI arguments); the response is one line of JSON chosen by
/// the app; then the connection closes.
public enum IPC {
    public static var socketPath: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mielwm/mielwm.sock").path
    }
}

public enum IPCError: Error, Equatable {
    case pathTooLong
    case alreadyRunning // another server answers on the path
    case notRunning // nobody listens on the path
    case system(String, Int32) // failing call and errno
    case badResponse
}

public final class IPCServer {
    /// Runs on the main queue. Call `reply` once, from any thread.
    public typealias Handler = (_ args: [String], _ reply: @escaping (Data) -> Void) -> Void

    private let path: String
    private let source: DispatchSourceRead

    /// Throws `.alreadyRunning` if another instance serves `path`; a stale
    /// socket file from a crash is replaced.
    public init(path: String = IPC.socketPath, handler: @escaping Handler) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var addr = try socketAddress(path)
        if let probe = try? connectSocket(path) {
            close(probe)
            throw IPCError.alreadyRunning
        }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw IPCError.system("socket", errno) }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else {
            let error = IPCError.system("bind", errno)
            close(fd)
            throw error
        }
        self.path = path
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "mielwm.ipc"))
        source.setEventHandler {
            let client = accept(fd, nil, nil)
            // Off the accept queue, so a silent client cannot hold up the next one.
            if client >= 0 { DispatchQueue.global().async { Self.serve(client, handler) } }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    public func stop() {
        guard !source.isCancelled else { return }
        source.cancel()
        unlink(path)
    }

    deinit { stop() }

    private static func serve(_ client: Int32, _ handler: @escaping Handler) {
        guard configure(client, timeout: 2), let line = readLine(client) else {
            close(client)
            return
        }
        guard let args = try? JSONDecoder().decode([String].self, from: line) else {
            writeLine(client, Data(#"{"error":"bad request"}"#.utf8))
            close(client)
            return
        }
        // A second reply must not write to a descriptor that may be reused.
        let replied = OSAllocatedUnfairLock(initialState: false)
        DispatchQueue.main.async {
            handler(args) { data in
                let first = replied.withLock { done in
                    defer { done = true }
                    return !done
                }
                guard first else { return }
                writeLine(client, data)
                close(client)
            }
        }
    }
}

public enum IPCClient {
    /// Sends `args` and returns the app's one-line JSON response.
    /// Throws `.notRunning` when no app listens.
    public static func send(_ args: [String], path: String = IPC.socketPath, timeout: TimeInterval = 5) throws -> Data {
        let fd = try connectSocket(path)
        defer { close(fd) }
        guard configure(fd, timeout: timeout) else { throw IPCError.notRunning }
        writeLine(fd, try JSONEncoder().encode(args))
        guard let line = readLine(fd) else { throw IPCError.badResponse }
        return line
    }
}

// MARK: - Sockets

private func socketAddress(_ path: String) throws -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw IPCError.pathTooLong }
    withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
    return addr
}

func connectSocket(_ path: String) throws -> Int32 {
    var addr = try socketAddress(path)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw IPCError.system("socket", errno) }
    let result = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard result == 0 else {
        close(fd)
        throw IPCError.notRunning
    }
    return fd
}

/// Timeouts, and no SIGPIPE on writes. False once the peer has hung up: the
/// socket then refuses options, and a write would raise SIGPIPE.
private func configure(_ fd: Int32, timeout: TimeInterval) -> Bool {
    var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - timeout.rounded(.down)) * 1_000_000))
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    var on: Int32 = 1
    return setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size)) == 0
}

/// Bytes up to the first newline, or up to EOF. nil on timeout, error, an
/// empty stream, or more than 1 MB without a newline.
func readLine(_ fd: Int32) -> Data? {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while data.count < 1 << 20 {
        let n = read(fd, &buffer, buffer.count)
        if n <= 0 { return n == 0 && !data.isEmpty ? data : nil }
        if let newline = buffer[..<n].firstIndex(of: UInt8(ascii: "\n")) {
            return data + buffer[..<newline]
        }
        data.append(contentsOf: buffer[..<n])
    }
    return nil
}

func writeLine(_ fd: Int32, _ data: Data) {
    let bytes = [UInt8](data) + [UInt8(ascii: "\n")]
    var offset = 0
    while offset < bytes.count {
        let n = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        if n <= 0 { return }
        offset += n
    }
}
