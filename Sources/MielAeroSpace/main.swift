import Foundation
import MielIPC
import os

// Two jobs, one binary (docs/aerospace.md):
//
//   aerospace <command>          Contents/Helpers/aerospace: answers Barik's AeroSpace
//                                commands from the running mielwm
//   AeroSpace --mielwm-pid <pid> Contents/Helpers/AeroSpace.app: shows Barik a running
//                                app called AeroSpace, until mielwm exits
//
// Barik runs the command four times every few seconds, so it starts fast and
// never waits long: no mielwm, or no answer within 0.3 s, prints what an
// AeroSpace with no windows would (`[]` for a list, nothing for an action).

let args = Array(CommandLine.arguments.dropFirst())

if args.first == "--mielwm-pid" {
    guard args.count == 2, let pid = pid_t(args[1]), pid > 0 else { exit(2) }
    let exited = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
    exited.setEventHandler { exit(0) }
    exited.resume()
    if kill(pid, 0) != 0, errno == ESRCH { exit(0) } // gone before the watch began
    dispatchMain()
}

let reply = try? IPCClient.send(["aerospace"] + args, timeout: 0.3)
if let reply, reply.starts(with: Data(#"{"error""#.utf8)) {
    Logger(subsystem: "my.miel.mielwm", category: "aerospace")
        .error("aerospace: unknown command: \(args.joined(separator: " "), privacy: .public)")
    exit(0)
}
let fallback = args.first?.hasPrefix("list-") == true ? "[]\n" : ""
FileHandle.standardOutput.write(reply.map { $0.isEmpty ? $0 : $0 + Data("\n".utf8) } ?? Data(fallback.utf8))
