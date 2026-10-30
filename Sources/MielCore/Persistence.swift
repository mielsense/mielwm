import CoreGraphics
import Foundation

/// One window as the layout file keeps it.
public struct SavedWindow: Hashable, Codable, Sendable {
    public var id: WindowID? // only meaningful while that window lives (crash recovery)
    public var bundleID: String?
    public var appName: String
    public var title: String
    public var ordinal: Int // among saved windows with the same bundle id and title
    public var frame: CGRect // canvas
    public var deskFrame: CGRect // where it really was (the park slot when parked)
    public var parked: Bool
    public var workspace: Int? // its workspace's slot; nil floats (version 2 on)
    public var weight: Double?
    public var position: Int? // in its workspace's tile order

    public init(id: WindowID?, bundleID: String?, appName: String, title: String, ordinal: Int, frame: CGRect,
                deskFrame: CGRect, parked: Bool, workspace: Int? = nil, weight: Double? = nil, position: Int? = nil) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.ordinal = ordinal
        self.frame = frame
        self.deskFrame = deskFrame
        self.parked = parked
        self.workspace = workspace
        self.weight = weight
        self.position = position
    }
}

public struct SavedWorkspace: Hashable, Codable, Sendable {
    public var slot: Int // its number up to 9
    public var mode: LayoutMode
    public var orientation: TileOrientation

    public init(slot: Int, mode: LayoutMode, orientation: TileOrientation) {
        self.slot = slot
        self.mode = mode
        self.orientation = orientation
    }
}

/// Canvas frames and the camera, saved to Application Support so windows
/// come back to their spots, and so `mielwm --watch` can unpark
/// everything if the app dies.
public struct LayoutSnapshot: Hashable, Codable, Sendable {
    public var version = 2 // 2 added workspaces
    public var camera: Camera
    public var deskCenter: CGPoint // the camera means something relative to it
    public var windows: [SavedWindow]
    public var slots: SlotGrid?
    public var workspaces: [SavedWorkspace]?
    public var current: Int?

    public init(camera: Camera, deskCenter: CGPoint, windows: [SavedWindow]) {
        self.camera = camera
        self.deskCenter = deskCenter
        self.windows = windows
    }

    public init(_ state: CanvasState) {
        var seen: [String: Int] = [:]
        windows = state.windows.map { w in
            let key = (w.bundleID ?? "") + "\u{1}" + w.displayTitle
            let ordinal = seen[key, default: 0]
            seen[key] = ordinal + 1
            let frame = w.pinned.map { state.deskCamera.toCanvas($0, deskCenter: state.deskCenter) } ?? w.frame
            let ws = state.workspace(of: w.id)
            return SavedWindow(id: w.id, bundleID: w.bundleID, appName: w.appName, title: w.displayTitle, ordinal: ordinal,
                               frame: frame, deskFrame: w.expected?.frame ?? w.real, parked: w.parked,
                               workspace: ws?.slot, weight: ws?.weights[w.id], position: ws?.members.firstIndex(of: w.id))
        }
        camera = state.deskCamera
        deskCenter = state.deskCenter
        slots = state.slots
        workspaces = state.workspaces.map { SavedWorkspace(slot: $0.slot, mode: $0.mode, orientation: $0.orientation) }
        current = state.currentWorkspace
    }

    /// ~/Library/Application Support/mielwm/layout.json
    public static func standardURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/mielwm/layout.json")
    }

    /// nil when missing or damaged; hand-edited junk never reaches window geometry.
    public static func load(from url: URL) -> LayoutSnapshot? {
        guard let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(LayoutSnapshot.self, from: data) else { return nil }
        func sane(_ v: CGFloat, _ limit: CGFloat) -> Bool { v.isFinite && abs(v) <= limit }
        func saneRect(_ r: CGRect) -> Bool {
            sane(r.minX, 1e6) && sane(r.minY, 1e6) && sane(r.width, 16384) && sane(r.height, 16384) && r.width >= 1 && r.height >= 1
        }
        guard sane(s.camera.center.x, 1e6), sane(s.camera.center.y, 1e6), sane(s.deskCenter.x, 1e6), sane(s.deskCenter.y, 1e6),
              s.camera.zoom > 0, sane(s.camera.zoom, 100) else { return nil }
        var clean = s
        clean.windows = s.windows.filter { saneRect($0.frame) && saneRect($0.deskFrame) }.map { w in
            var w = w
            if !(w.workspace.map { (1 ... 1000).contains($0) } ?? true) { w.workspace = nil }
            if !(w.weight.map { $0.isFinite && $0 > 0 && $0 < 100 } ?? true) { w.weight = nil }
            return w
        }
        if let g = s.slots, !(sane(g.origin.x, 1e6) && sane(g.origin.y, 1e6) && g.step >= 100 && sane(g.step, 1e5)) { clean.slots = nil }
        clean.workspaces = s.workspaces?.filter { (1 ... 1000).contains($0.slot) && $0.mode != .floating }
        return clean
    }

    public func save(to url: URL) throws {
        try writeJSON(self, to: url)
    }

    /// The saved window a newly seen one is: the same window id and bundle id
    /// (its app kept running, so the title may have changed); failing that the
    /// same bundle id, title and ordinal; failing that the first unclaimed one
    /// with the same bundle id and title.
    func match(id: WindowID, bundleID: String?, title: String, ordinal: Int, excluding claimed: Set<Int>) -> Int? {
        if let k = windows.indices.first(where: { !claimed.contains($0) && windows[$0].id == id && windows[$0].bundleID == bundleID }) {
            return k
        }
        let same = windows.indices.filter { !claimed.contains($0) && windows[$0].bundleID == bundleID && windows[$0].title == title }
        return same.first { windows[$0].ordinal == ordinal } ?? same.first
    }
}

/// For crash recovery (`mielwm --watch`): every window the snapshot had
/// parked, back onto a screen.
public func unparkCommands(_ snapshot: LayoutSnapshot, screens: [ScreenInfo]) -> [WindowCommand] {
    snapshot.windows.compactMap { w in
        guard let id = w.id, w.parked || isHiddenFrame(w.deskFrame, screens: screens) else { return nil }
        let desk = snapshot.camera.toDesk(w.frame, deskCenter: snapshot.deskCenter)
        return .setFrame(id, onScreenFrame(desk, screens: screens).roundedFrame)
    }
}
