import Foundation
import MielCore
@testable import mielwm
import Testing

// What the socket answers, on a controller that never starts: no windows, nothing moves.

@MainActor
private func answer(_ controller: Controller, _ args: [String]) -> String {
    var out: String?
    controller.command(args) { out = String(decoding: $0, as: UTF8.self) }
    return out ?? "no reply"
}

@MainActor @Test func stateDescribesTheCanvas() throws {
    let controller = Controller(mode: .manageOnly(getpid()), paths: try scratchConfig())
    let state = try JSONSerialization.jsonObject(with: Data(answer(controller, ["state"]).utf8)) as? [String: Any]
    #expect(state?["overview"] as? Bool == false)
    #expect((state?["windows"] as? [Any])?.isEmpty == true)
}

@MainActor @Test func anUnknownActionIsAnError() throws {
    let controller = Controller(mode: .manageOnly(getpid()), paths: try scratchConfig())
    #expect(answer(controller, ["frobnicate"]) == #"{"error":"unknown action"}"#)
}

@MainActor @Test func theAerospaceCommandReadsTheCanvas() throws {
    let controller = Controller(mode: .manageOnly(getpid()), paths: try scratchConfig())
    #expect(answer(controller, ["aerospace", "list-windows", "--all", "--json"]) == "[]")
    #expect(answer(controller, ["aerospace", "list-workspaces", "--focused"]) == #"{"error":"unknown command"}"#) // no --json
    #expect(answer(controller, ["aerospace", "workspace", "x"]) == #"{"error":"unknown command"}"#)
}
