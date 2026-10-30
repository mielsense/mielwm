import CoreGraphics
import Foundation

// MARK: - What Render draws

public struct SceneWindow: Hashable, Sendable {
    public var id: WindowID
    public var canvasFrame: CGRect
    public var title: String
    public var appName: String
    public var bundleID: String?
    public var dim: Double // 0 full emphasis ... 1 fully receded
    public var isSelected: Bool
    public var isFocused: Bool
    public var isPinned: Bool // pinned windows ignore the camera: canvasFrame is a desk frame

    public init(id: WindowID, canvasFrame: CGRect, title: String, appName: String,
                bundleID: String? = nil, dim: Double = 0, isSelected: Bool = false,
                isFocused: Bool = false, isPinned: Bool = false) {
        self.id = id
        self.canvasFrame = canvasFrame
        self.title = title
        self.appName = appName
        self.bundleID = bundleID
        self.dim = dim
        self.isSelected = isSelected
        self.isFocused = isFocused
        self.isPinned = isPinned
    }
}

/// A workspace's frame on the canvas: the screen-sized area its tiles fill.
public struct SceneWorkspace: Hashable, Sendable {
    public var number: Int? // 1...9, nil past 9
    public var canvasFrame: CGRect
    public var mode: LayoutMode // .tiles or .stack
    public var isCurrent: Bool // the one the camera rests on (or last rested on)
    /// Shown in an empty workspace, `{...}` as keycaps ("Workspace 4 is empty  {⌥⇧4} Move a window here").
    public var emptyMessage = ""

    public init(number: Int?, canvasFrame: CGRect, mode: LayoutMode, isCurrent: Bool = false) {
        self.number = number
        self.canvasFrame = canvasFrame
        self.mode = mode
        self.isCurrent = isCurrent
    }
}

public struct HUDRow: Hashable, Sendable {
    public var title: String
    public var detail: String
    public var bundleID: String? // app icon
    public var trailing: String // shortcut hint ("⌘1")
    public var highlights: [Range<Int>] // matched character offsets in `title`

    public init(title: String, detail: String = "", bundleID: String? = nil,
                trailing: String = "", highlights: [Range<Int>] = []) {
        self.title = title
        self.detail = detail
        self.bundleID = bundleID
        self.trailing = trailing
        self.highlights = highlights
    }
}

public struct HelpSection: Hashable, Sendable {
    public var title: String
    public var entries: [(keys: String, action: String)]

    public init(title: String, entries: [(keys: String, action: String)]) {
        self.title = title
        self.entries = entries
    }

    public static func == (a: HelpSection, b: HelpSection) -> Bool {
        a.title == b.title && a.entries.elementsEqual(b.entries) { $0.keys == $1.keys && $0.action == $1.action }
    }

    public func hash(into h: inout Hasher) {
        h.combine(title)
        for e in entries { h.combine(e.keys); h.combine(e.action) }
    }
}

public struct HUDModel: Hashable, Sendable {
    public enum Mode: Hashable, Sendable { case hidden, search, switcher, help }

    public var mode: Mode = .hidden
    public var query = ""
    public var markedText = "" // input-method composition in progress (a dead key before its letter)
    public var placeholder = "Search windows"
    public var rows: [HUDRow] = [] // search results or switcher entries
    public var selectedRow: Int?
    public var footer = "" // search: how many more results
    public var readout = "" // top right: zoom, window count, display
    public var hints = "" // bottom: the keys that work now
    public var help: [HelpSection] = []
    public var toast: String? // short notice, e.g. "Tidied 12 windows"

    public init() {}
}

public struct MinimapModel: Hashable, Sendable {
    public var windows: [(frame: CGRect, dim: Double)] // canvas frames
    public var focusedIndex: Int?
    public var viewport: CGRect // canvas rect the desk currently shows
    public var showsArrangeButton = true
    public var workspaces: [CGRect] = [] // canvas frames of the workspaces

    public init(windows: [(frame: CGRect, dim: Double)], focusedIndex: Int?, viewport: CGRect) {
        self.windows = windows
        self.focusedIndex = focusedIndex
        self.viewport = viewport
    }

    public static func == (a: MinimapModel, b: MinimapModel) -> Bool {
        a.windows.map(\.frame) == b.windows.map(\.frame) && a.windows.map(\.dim) == b.windows.map(\.dim)
            && a.focusedIndex == b.focusedIndex && a.viewport == b.viewport
            && a.showsArrangeButton == b.showsArrangeButton && a.workspaces == b.workspaces
    }

    public func hash(into h: inout Hasher) {
        h.combine(viewport.origin.x); h.combine(viewport.origin.y); h.combine(focusedIndex)
        h.combine(windows.count)
    }
}

/// Everything one overlay (one display) draws in one frame.
public struct Scene: Equatable, Sendable {
    public var screen: ScreenInfo // the display being drawn
    public var desk: CGRect // union of all screen frames
    public var camera: Camera
    /// 0 = the plain desktop at 100% (no lens, no backdrop, no chrome),
    /// 1 = fully zoomed-out overview. Lens, dim, grid and chrome scale with it.
    public var transition: Double
    public var opacity: Double // the whole overlay, for the landing fade
    public var windows: [SceneWindow] // back to front
    public var look: Look
    public var minimap: MinimapModel?
    public var hud: HUDModel
    public var dropIndicator: CGRect? // canvas rect where a dragged window will land
    public var time: Double // seconds, for the window names' fades
    public var workspaces: [SceneWorkspace] = [] // drawn behind the windows, with the transition
    /// A search is on: windows that match get an outline. Its own field, since
    /// the HUD is drawn elsewhere (the overlay's native views).
    public var searching = false

    public init(screen: ScreenInfo, desk: CGRect, camera: Camera, transition: Double,
                opacity: Double = 1, windows: [SceneWindow], look: Look,
                minimap: MinimapModel? = nil, hud: HUDModel = HUDModel(),
                dropIndicator: CGRect? = nil, time: Double = 0) {
        self.screen = screen
        self.desk = desk
        self.camera = camera
        self.transition = transition
        self.opacity = opacity
        self.windows = windows
        self.look = look
        self.minimap = minimap
        self.hud = hud
        self.dropIndicator = dropIndicator
        self.time = time
    }
}

// MARK: - Building a scene

public extension CanvasState {
    /// Everything one overlay draws this frame.
    func scene(for screen: ScreenInfo, time: Double? = nil) -> Scene {
        let look = self.look
        let matches = isOverview ? overview.matchSet : nil
        let sceneWindows = drawnWindows.map { w, frame in
            SceneWindow(id: w.id, canvasFrame: frame, title: w.displayTitle, appName: w.appName, bundleID: w.bundleID,
                        dim: matches.map { $0.contains(w.id) ? 0 : look.dimUnmatched } ?? 0,
                        isSelected: isOverview && w.id == selection && (matches?.contains(w.id) ?? true), isFocused: w.id == focused, isPinned: w.pinned != nil)
        }
        let minimap = look.minimapEnabled && animator.transition > 0.001 ? minimapModel(for: screen) : nil
        var scene = Scene(screen: screen, desk: deskRect(screens), camera: camera, transition: animator.transition,
                          windows: sceneWindows, look: look, minimap: minimap, hud: hud(for: screen),
                          dropIndicator: dropIndicator, time: time ?? now)
        scene.searching = scene.hud.mode == .search && !scene.hud.query.isEmpty
        scene.workspaces = workspaces.map {
            var ws = SceneWorkspace(number: $0.number, canvasFrame: workspaceFrame($0.slot), mode: $0.mode,
                                    isCurrent: $0.slot == currentWorkspace)
            if $0.members.isEmpty { ws.emptyMessage = emptyMessage($0.slot) }
            return ws
        }
        return scene
    }

    /// The shown windows back to front, where the overview draws them
    /// (pinned ones at their desk frames). Zoomed out, a stack reads as a
    /// deck of cards: each window behind peeks out above the one in front, a
    /// little narrower, up to three deep; the selected member comes to the
    /// front, so browsing a stack shows each window.
    internal var drawnWindows: [(window: ManagedWindow, frame: CGRect)] {
        let shown = windows.filter(\.isShown)
        var ordered = shown.filter { $0.pinned == nil } + shown.filter { $0.pinned != nil } // pinned on top
        var fan: [WindowID: CGRect] = [:]
        for ws in workspaces where ws.mode == .stack {
            let members = Set(ws.members)
            let spots = ordered.indices.filter { members.contains(ordered[$0].id) && ordered[$0].pinned == nil }
            var stacked = spots.map { ordered[$0] }
            if isOverview, let s = selection, let i = stacked.firstIndex(where: { $0.id == s }) { stacked.append(stacked.remove(at: i)) }
            for (spot, w) in zip(spots, stacked) { ordered[spot] = w } // the same places in the z-order, the selection last
            for (depth, w) in stacked.reversed().enumerated() {
                let d = CGFloat(min(depth, 3)) * animator.transition
                fan[w.id] = w.frame.insetBy(dx: 24 * d, dy: 0).offsetBy(dx: 0, dy: -14 * d)
            }
        }
        return ordered.map { ($0, $0.pinned ?? fan[$0.id] ?? $0.frame) }
    }

    /// "Workspace 4 is empty", with the live chord that moves a window there.
    func emptyMessage(_ slot: Int) -> String {
        let name = slot <= 9 ? "Workspace \(slot) is empty" : "This workspace is empty"
        let chords = settings.chords.filter { $0.value == .moveToWorkspace(slot) }.map(\.key.symbol)
        guard let chord = chords.min(by: { ($0.count, $0) < ($1.count, $1) }) else { return name }
        return name + "  {\(chord)} Move a window here"
    }

    /// The minimap's contents for one screen: canvas frames, matches dimmed,
    /// and the canvas rect that screen shows.
    func minimapModel(for screen: ScreenInfo) -> MinimapModel {
        let matches = isOverview ? overview.matchSet : nil
        let shown = candidates
        let marked = selection ?? focused
        var model = MinimapModel(windows: shown.map { w in (w.frame, matches.map { $0.contains(w.id) ? 0 : 0.78 } ?? 0) },
                                 focusedIndex: shown.firstIndex { $0.id == marked },
                                 viewport: camera.toCanvas(screen.frame, deskCenter: deskCenter))
        model.showsArrangeButton = isOverview
        model.workspaces = workspaces.map { workspaceFrame($0.slot) }
        return model
    }

    /// The minimap's layout on one screen, for hit testing a click.
    func minimapLayout(for screen: ScreenInfo) -> MinimapLayout {
        let m = minimapModel(for: screen)
        return MielCore.minimapLayout(screenSize: screen.frame.size, look: look, windows: m.windows.map(\.frame), viewport: m.viewport,
                                           workspaces: m.workspaces)
    }

    /// The canvas point under a screen-local point, through the lens.
    func canvasPoint(atScreenPoint p: CGPoint, on screen: ScreenInfo) -> CGPoint {
        camera.toCanvas(deskPoint(atScreenPoint: p, on: screen), deskCenter: deskCenter)
    }

    /// The desk point the lens shows at a screen-local point.
    func deskPoint(atScreenPoint p: CGPoint, on screen: ScreenInfo) -> CGPoint {
        let source = lensSourcePoint(p, screenSize: screen.frame.size, look: look, transition: animator.transition)
        return CGPoint(x: source.x + screen.frame.minX, y: source.y + screen.frame.minY)
    }

    /// The frontmost window under a screen-local point, as drawn: pinned
    /// windows at their desk frames, stacks fanned out.
    func window(atScreenPoint p: CGPoint, on screen: ScreenInfo) -> WindowID? {
        let desk = deskPoint(atScreenPoint: p, on: screen), c = camera.toCanvas(desk, deskCenter: deskCenter)
        return drawnWindows.last { $0.frame.contains($0.window.pinned == nil ? c : desk) }?.window.id
    }
}
