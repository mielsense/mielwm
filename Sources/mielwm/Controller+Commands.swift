import AppKit
import MielCore
import MielIPC
import MielRender
import MielSystem
import QuartzCore

extension Controller {
    /// What the menu bar shows: the workspaces with windows, and the current one with its layout.
    struct WorkspaceStatus: Equatable {
        var numbers: [Int]
        var current: Int?
        var mode: LayoutMode?
    }

    var workspaceStatus: WorkspaceStatus {
        let current = state.currentWorkspace.flatMap { $0 <= 9 ? $0 : nil }
        let numbers = Set(state.workspaces.filter { !$0.members.isEmpty }.compactMap(\.number) + (current.map { [$0] } ?? []))
        return WorkspaceStatus(numbers: numbers.sorted(), current: current, mode: state.workspaces.first { $0.slot == current }?.mode)
    }

    func reportWorkspaces() {
        guard let onWorkspaces else { return }
        let status = workspaceStatus
        guard status != reportedWorkspaces else { return }
        reportedWorkspaces = status
        onWorkspaces(status)
    }

    /// The Settings window's values while they change (a slider moving), before config.json has them.
    func applyLive(_ settings: Settings) {
        if settings != state.settings { input(.setSettings(settings)) }
    }

    // MARK: Socket commands

    func command(_ args: [String], _ reply: @escaping (Data) -> Void) {
        if args.first == "aerospace" { // Barik, through the `aerospace` command: read from the canvas, no Accessibility
            switch state.aerospace(Array(args.dropFirst())) {
            case let .output(json): return reply(Data(json.utf8))
            case let .input(event): event.map(input)
            case .unknown: return reply(Data(#"{"error":"unknown command"}"#.utf8))
            }
            return reply(Data())
        }
        let text = args.joined(separator: " ")
        switch text {
        case "state":
            reply(stateJSON())
        case "quit":
            reply(Data(#"{"ok":true}"#.utf8))
            DispatchQueue.main.async { NSApp.terminate(nil) }
        default:
            guard let action = Action(command: text) else {
                return reply(Data(#"{"error":"unknown action"}"#.utf8))
            }
            input(.action(action))
            reply(Data(#"{"ok":true}"#.utf8))
        }
    }

    func stateJSON() -> Data {
        struct Window: Encodable {
            var id: String, app: String, title: String, frame: [Double], real: [Double]
            var parked: Bool, pinned: Bool, minimized: Bool, hidden: Bool
        }
        struct Dump: Encodable {
            var overview: Bool, zoom: Double, camera: [Double], deskCamera: [Double]
            var focused: String?, selection: String?, windows: [Window], screens: [String]
        }
        func r(_ f: CGRect) -> [Double] { [f.minX, f.minY, f.width, f.height] }
        let s = state
        let dump = Dump(overview: s.isOverview, zoom: s.camera.zoom, camera: [s.camera.center.x, s.camera.center.y],
                        deskCamera: [s.deskCamera.center.x, s.deskCamera.center.y],
                        focused: s.focused?.description, selection: s.selection?.description,
                        windows: s.windows.map {
                            Window(id: $0.id.description, app: $0.appName, title: $0.title, frame: r($0.frame), real: r($0.real),
                                   parked: $0.parked, pinned: $0.pinned != nil, minimized: $0.isMinimized, hidden: $0.isHidden)
                        },
                        screens: s.screens.map(\.name))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(dump)) ?? Data("{}".utf8)
    }
}
