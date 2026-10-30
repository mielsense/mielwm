import CoreGraphics
import Foundation

// The small panels the app shows over the desktop, outside the overview: a
// toast, the workspace you just switched to, and the windows of a stack.
// Core decides what each shows, on which display and until when; the app
// only draws them.

/// One notice: what it shows, on which display, and when it starts to fade.
public struct Notice<Content: Equatable & Sendable>: Equatable, Sendable {
    public var content: Content
    public var screenID: UInt32
    public var until: Double // full opacity until then, then it fades out over `Notices.fade`

    /// 1 while it holds, then down to 0 over `Notices.fade`.
    public func opacity(at time: Double) -> Double {
        min(1, max(0, 1 - (time - until) / Notices.fade))
    }
}

/// The workspace pill: the numbers of the workspaces with windows, the current one filled.
public struct WorkspaceNotice: Equatable, Sendable {
    public var numbers: [Int]
    public var current: Int
    public var mode: LayoutMode
    public var windowCount: Int

    public init(numbers: [Int], current: Int, mode: LayoutMode, windowCount: Int) {
        self.numbers = numbers
        self.current = current
        self.mode = mode
        self.windowCount = windowCount
    }

    /// What VoiceOver says: "Workspace 3, stack, 4 windows".
    public var spoken: String {
        let layout = mode == .stack ? "stack, " : ""
        return "Workspace \(current), \(layout)\(windowCount) \(windowCount == 1 ? "window" : "windows")"
    }
}

/// The stack strip: the stacked windows in their order, the front one marked.
public struct StackNotice: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public var bundleID: String?
        public var title: String

        public init(bundleID: String?, title: String) {
            self.bundleID = bundleID
            self.title = title
        }
    }

    public var entries: [Entry]
    public var front: Int
    /// The stack's tile area in desk points: the strip sits at its top.
    public var area: CGRect

    public init(entries: [Entry], front: Int, area: CGRect) {
        self.entries = entries
        self.front = front
        self.area = area
    }

    /// "2 of 4".
    public var position: String { "\(front + 1) of \(entries.count)" }
}

public struct Notices: Equatable, Sendable {
    static let hold = 0.7 // seconds the workspace and stack notices stay
    public static let fade = 0.15

    /// A short message, e.g. "Tidied 12 windows". The overview's overlay draws it while
    /// it is up; one raised outside the overview also shows in a panel.
    public internal(set) var toast: Notice<String>?
    public internal(set) var toastInOverview = false
    public internal(set) var workspace: Notice<WorkspaceNotice>?
    public internal(set) var stack: Notice<StackNotice>?

    public var isEmpty: Bool { toast == nil && workspace == nil && stack == nil }

    /// Drops what has faded out.
    mutating func expire(_ now: Double) {
        if let n = toast, n.opacity(at: now) <= 0 { toast = nil }
        if let n = workspace, n.opacity(at: now) <= 0 { workspace = nil }
        if let n = stack, n.opacity(at: now) <= 0 { stack = nil }
    }
}

/// What an input may change that the notices watch: the current workspace,
/// and the stack on screen by its windows and its front one.
struct NoticeWatch: Equatable {
    var overview: Bool
    var workspace: Int?
    var stack: [WindowID]?
    var front: WindowID?
}

extension CanvasState {
    var noticeWatch: NoticeWatch {
        let face = stackFace
        return NoticeWatch(overview: isOverview, workspace: currentWorkspace, stack: face?.ids, front: face?.front)
    }

    /// The stack on screen at 100%: the current workspace, resting on a
    /// display, stacked, with two or more windows shown.
    private var stackFace: (ws: Workspace, screen: ScreenInfo, ids: [WindowID], front: WindowID)? {
        guard !isOverview, let rest = restingSlot(deskCamera), rest.slot == currentWorkspace,
              let k = workspaceIndex(rest.slot), workspaces[k].mode == .stack else { return nil }
        let ws = workspaces[k], ids = ws.members.filter { window($0)?.isShown ?? false }
        guard ids.count >= 2, let front = frontMember(ids) else { return nil }
        return (ws, rest.screen, ids, front)
    }

    /// The numbers of the workspaces with windows, and `current`, as the menu bar and the pill show them.
    public func workspaceNumbers(current: Int?) -> [Int] {
        Set(workspaces.filter { !$0.members.isEmpty }.compactMap(\.number) + (current.map { [$0] } ?? [])).sorted()
    }

    /// The one of `ids` highest in the window order.
    func frontMember(_ ids: [WindowID]) -> WindowID? {
        let set = Set(ids)
        return windows.last { set.contains($0.id) }?.id
    }

    /// After an input: a toast, a workspace switch or a stack that changed shows.
    mutating func updateNotices(from before: NoticeWatch) {
        let after = noticeWatch
        guard after != before, !after.overview, !before.overview else { return }
        if after.workspace != before.workspace, settings.workspaceNotice, let current = currentWorkspace, current <= 9 {
            let numbers = workspaceNumbers(current: current)
            let ws = workspaceIndex(current).map { workspaces[$0] }
            let count = ws?.members.count { window($0)?.isShown ?? false } ?? 0
            let content = WorkspaceNotice(numbers: numbers, current: current, mode: ws?.mode ?? .tiles, windowCount: count)
            let screen = restingSlot(deskCamera)?.screen ?? activeScreen
            notices.workspace = Notice(content: content, screenID: screen.id, until: now + Notices.hold)
        }
        if after.stack != before.stack || after.front != before.front {
            guard let face = stackFace, let front = face.ids.firstIndex(of: face.front) else { return notices.stack = nil }
            let entries = face.ids.compactMap(window).map { StackNotice.Entry(bundleID: $0.bundleID, title: $0.displayTitle) }
            let content = StackNotice(entries: entries, front: front, area: settings.tileArea(on: face.screen))
            notices.stack = Notice(content: content, screenID: face.screen.id, until: now + Notices.hold)
        }
    }

    /// What VoiceOver says for the ⌥Tab strip once it shows: the selected window's app.
    public var switcherSpeech: String? {
        guard overview.switcherRevealed(now: now), !isOverview, let id = overview.selectedWindow else { return nil }
        return window(id)?.appName
    }
}
