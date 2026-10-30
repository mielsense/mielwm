import Darwin
import Dispatch
import os

// Two jobs, one binary (docs/aerospace.md):
//
//   aerospace <command>          Contents/Helpers/aerospace: answers Barik's AeroSpace
//                                commands from the running mielwm
//   AeroSpace --mielwm-pid <pid> Contents/Helpers/AeroSpace.app: shows Barik a running
//                                app called AeroSpace, until mielwm exits
//
// Status bars like Barik run the command up to 40 times a second, so it starts fast and
// never waits long: no mielwm, no answer within 0.3 s, or a command mielwm
// doesn't know prints what an AeroSpace with no windows would (`[]` for a
// list, nothing for an action).
//
// No Foundation: loading it doubles the cost of each call. It speaks MielIPC's
// protocol (one JSON array of strings, one line back) with plain sockets.

let args = Array(CommandLine.arguments.dropFirst())

if args.first == "--mielwm-pid" {
    guard args.count == 2, let pid = pid_t(args[1]), pid > 0 else { exit(2) }
    let exited = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
    exited.setEventHandler { exit(0) }
    exited.resume()
    if kill(pid, 0) != 0, errno == ESRCH { exit(0) } // gone before the watch began
    dispatchMain()
}

var reply = send(["aerospace"] + args, to: socketPath(), timeout: 0.3)
if let answer = reply, answer.starts(with: Array(#"{"error""#.utf8)) {
    Logger(subsystem: "my.miel.mielwm", category: "aerospace")
        .error("aerospace: unknown command: \(args.joined(separator: " "), privacy: .public)")
    reply = nil
}
let fallback = args.first?.hasPrefix("list-") == true ? "[]\n" : ""
let out = reply.map { $0.isEmpty ? $0 : $0 + [UInt8(ascii: "\n")] } ?? Array(fallback.utf8)
writeAll(STDOUT_FILENO, out)

/// IPC.socketPath: `MIELWM_SOCKET`, else Application Support in the home
/// folder the user database names, which is where Foundation looks too.
func socketPath() -> String {
    if let path = getenv("MIELWM_SOCKET") { return String(cString: path) }
    let home = getpwuid(getuid()).flatMap { $0.pointee.pw_dir.map { String(cString: $0) } } ?? ""
    return home + "/Library/Application Support/mielwm/mielwm.sock"
}

/// IPCClient.send: the reply line without its newline, or nil when nobody
/// listens, nothing comes back within `timeout`, or the reply passes 1 MB.
func send(_ args: [String], to path: String, timeout: Double) -> [UInt8]? {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
    withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    let connected = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - timeout.rounded(.down)) * 1_000_000))
    var on: Int32 = 1
    guard connected == 0,
          setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size)) == 0,
          setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size)) == 0,
          setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size)) == 0
    else { return nil }
    guard writeAll(fd, Array(("[" + args.map(json).joined(separator: ",") + "]\n").utf8)) else { return nil }
    var line: [UInt8] = [], buffer = [UInt8](repeating: 0, count: 4096)
    while line.count < 1 << 20 {
        let n = read(fd, &buffer, buffer.count)
        if n <= 0 { return n == 0 && !line.isEmpty ? line : nil }
        if let newline = buffer[..<n].firstIndex(of: UInt8(ascii: "\n")) { return line + buffer[..<newline] }
        line += buffer[..<n]
    }
    return nil
}

/// False if `fd` stopped taking bytes before all of them were written.
@discardableResult
func writeAll(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
    var sent = 0
    while sent < bytes.count {
        let n = bytes[sent...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        if n <= 0 { return false }
        sent += n
    }
    return true
}

/// `s` as a JSON string.
func json(_ s: String) -> String {
    var out = "\""
    for u in s.unicodeScalars {
        switch u {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case _ where u.value < 0x20: out += "\\u00" + (u.value < 0x10 ? "0" : "") + String(u.value, radix: 16)
        default: out.unicodeScalars.append(u)
        }
    }
    return out + "\""
}
