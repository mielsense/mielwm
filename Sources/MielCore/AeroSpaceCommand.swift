import Foundation

// Status bars made for AeroSpace, like Barik, show workspaces by running the
// `aerospace` command. mielwm's own `aerospace` command
// (docs/compatible-apps.md) asks the running app, which answers here from
// the canvas.

/// What the app does with one `aerospace` command.
public enum AeroSpaceReply: Equatable, Sendable {
    case output(String) // a JSON array to print
    case input(CoreInput?) // an action to take (nil: its window is gone); prints nothing
    case unknown
}

public extension CanvasState {
    /// The commands Barik runs. Workspaces are named by slot number, windows by their CGWindowID.
    func aerospace(_ args: [String]) -> AeroSpaceReply {
        let flags = Set(args.dropFirst()), focusedOnly = flags.contains("--focused")
        let listing = flags.contains("--json") && (focusedOnly || flags.contains("--all"))
        switch args.first {
        case "list-workspaces" where listing:
            let slots = focusedOnly ? [currentWorkspace].compactMap { $0 } : workspaces.map(\.slot).sorted()
            return .output(aeroJSON(slots.map { ["workspace": String($0)] }))
        case "list-windows" where listing:
            // Floating windows belong to no workspace; Barik lists windows by workspace.
            let listed = focusedOnly ? windows.filter { $0.id == focused } : windows.filter { $0.workspace != nil }
            return .output(aeroJSON(listed.map(AeroWindow.init)))
        case "workspace" where args.count == 2:
            guard let n = Int(args[1]) else { return .unknown }
            return .input(.action(.workspace(n)))
        case "focus" where args.count == 3 && args[1] == "--window-id":
            guard let n = UInt32(args[2]) else { return .unknown }
            return .input(windows.first { $0.id.number == n }.map { .landOn($0.id) })
        case "workspace-back-and-forth", "close", "macos-native-minimize", "resize", "focus":
            // The commands that do here what they do in AeroSpace, by the same words. Not through
            // aeroSpaceCommand: the import maps ±50 to ⌥= and ⌥-, and its move and layout aren't AeroSpace's.
            let command = args == ["macos-native-minimize"] ? "minimize" : args.joined(separator: " ")
            return Action(command: command).map { .input(.action($0)) } ?? .unknown
        default:
            return .unknown
        }
    }
}

/// One window as `aerospace list-windows --json` prints it.
private struct AeroWindow: Encodable {
    var id: UInt32, app: String, title: String, workspace: String?

    enum CodingKeys: String, CodingKey {
        case id = "window-id", app = "app-name", title = "window-title", workspace
    }
}

private extension AeroWindow {
    init(_ w: ManagedWindow) {
        self.init(id: w.id.number, app: w.appName, title: w.title, workspace: w.workspace.map(String.init))
    }
}

private func aeroJSON(_ value: some Encodable) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
}
