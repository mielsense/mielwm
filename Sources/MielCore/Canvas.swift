import CoreGraphics
import Foundation

/// A window mielwm manages: standard and movable.
public struct ManagedWindow: Hashable, Sendable {
    public var id: WindowID
    public var bundleID: String?
    public var appName: String
    public var title: String
    public var frame: CGRect // canvas frame
    public var isMinimized = false
    public var isHidden = false // its app is hidden
    public var isFullScreen = false // in macOS full screen: it keeps its tile, but nobody moves it
    public var isResizable = true
    public var pinned: CGRect? // desk frame while pinned
    public var parked = false // sits in a park slot
    public var real: CGRect // what macOS last reported, or we last set
    public var workspace: Int? // its workspace's slot; nil floats
    var floatingFrame: CGRect? // where it last floated, for going back
    var reparks = 0
    var expected: Expectation?
    var pending: CGRect? // newest unconfirmed report while an expectation lives

    public var isShown: Bool { !isMinimized && !isHidden }
    var displayTitle: String { title.isEmpty ? appName : title }
}

/// A frame we asked for and are waiting to see reported.
struct Expectation: Hashable, Sendable {
    var frame: CGRect
    var deadline: Double
}

struct FullscreenEntry: Hashable, Sendable {
    var before: CGRect // canvas frame to go back to
    var suspended = false // ⌃⌥G took the screen back; landing on it again goes fullscreen again
}

/// What undo puts back: frames and the workspaces.
struct UndoEntry: Sendable {
    var frames: [WindowID: CGRect]
    var workspaces: [Workspace]
}

struct Checkpoint: Hashable, Sendable {
    var kind: String
    var window: WindowID?
    var time: Double
}

/// Everything Core knows. Change it only through `send` / `reduce`.
public struct CanvasState: Sendable {
    static let expectationLifetime = 1.0 // seconds a setFrame has to show up
    static let focusLifetime = 0.6 // seconds a focus we asked for has to show up
    static let frameTolerance: CGFloat = 2
    static let screenGracePeriod = 1.5
    static let maxReparks = 2
    static let toastDuration = 1.8
    static let undoDepth = 30

    public internal(set) var screens: [ScreenInfo]
    public var settings: Settings { didSet { settingsChanged(from: oldValue) } }
    public var systemAccent: RGB? { didSet { resolveLook() } } // what "auto" resolves to; the app sets it
    /// The system appearance; the app sets it.
    public var systemDark = true { didSet { resolveLook() } }
    /// Reduce Motion, Reduce Transparency, Increase Contrast; the app sets them.
    public var accessibility = AccessibilityOptions() { didSet { resolveLook() } }
    /// `settings.look` with the accent resolved, kept current so frames and hit tests don't re-resolve it.
    public private(set) var look: Look
    /// The screen the user acts on (pointer or keyboard). The HUD shows there
    /// and the camera frames windows for it. Falls back to the focused window's screen.
    public var activeScreenID: UInt32?
    /// Lowercase user and host names: words the tidy-up must not group by.
    public var stopwords: Set<String> = []
    public let ownPID: Int32

    public internal(set) var now: Double
    public internal(set) var windows: [ManagedWindow] = [] // back to front
    public internal(set) var animator: CameraAnimator
    /// The camera the real windows are laid out for (always zoom 1).
    public internal(set) var deskCamera: Camera
    public internal(set) var isOverview = false
    public internal(set) var isPanning = false
    public internal(set) var focused: WindowID?
    public internal(set) var selection: WindowID? // in the overview
    public internal(set) var mru = MRU()
    public internal(set) var overview = OverviewMachine()
    public internal(set) var dropIndicator: CGRect?
    public internal(set) var toast: String?
    /// Bumps when ⌘, (or the tune action) asks for the Settings window's Appearance pane.
    public internal(set) var appearanceRequests = 0
    /// Bumps when frames or the camera settle somewhere new; save the layout then.
    public internal(set) var layoutRevision = 0
    /// Workspaces with windows, and the current one even when empty, by slot.
    public internal(set) var workspaces: [Workspace] = []
    /// The workspace the desk camera rests on, or last rested on.
    public internal(set) var currentWorkspace: Int?
    public internal(set) var slots: SlotGrid

    var toastUntil = 0.0
    var returnCamera: Camera?
    var openedCamera: Camera? // where this overview session opened, to tell whether the camera moved since
    var fills: [WindowID: RestoreEntry] = [:]
    var fullscreens: [WindowID: FullscreenEntry] = [:]
    var undoStack: [UndoEntry] = []
    var redoStack: [UndoEntry] = []
    var lastCheckpoint: Checkpoint?
    var graceUntil: Double?
    var expectedFocus: (id: WindowID, until: Double)?
    var dragging: WindowID?
    var saved: LayoutSnapshot?
    var claimed = Set<Int>()
    var restoredPositions: [WindowID: Int] = [:] // tile order from the saved layout
    var restoreUntil: Double
    var outbox: [WindowCommand] = []

    /// `savedLayout` (from the last run) gives windows that come back their
    /// spots for the first 15 seconds.
    public init(screens: [ScreenInfo], settings: Settings = Settings(), ownPID: Int32, now: Double = 0,
                savedLayout: LayoutSnapshot? = nil) {
        self.screens = screens
        self.settings = settings
        self.ownPID = ownPID
        self.now = now
        look = settings.resolvedLook()
        let center = MielCore.deskCenter(screens)
        var camera = Camera(center: center)
        if let s = savedLayout, settings.rememberLayout {
            // Keep the offset between camera and desk, so a different set of screens still lines up.
            // Whole points from the desk center, as `roundedAtRest` keeps them (a desk can be an odd number of points tall).
            camera.center = CGPoint(x: center.x + (s.camera.center.x - s.deskCenter.x).rounded(),
                                    y: center.y + (s.camera.center.y - s.deskCenter.y).rounded())
            saved = s
        }
        deskCamera = camera
        animator = CameraAnimator(camera: camera, now: now, curve: settings.animationCurve, duration: settings.flightDuration)
        animator.enabled = settings.animationEnabled
        restoreUntil = now + 15
        slots = saved?.slots ?? SlotGrid(screens: screens, camera: camera)
        widenSlots()
        setCurrent(restingSlot(deskCamera)?.slot ?? saved?.current ?? 1)
    }

    /// `look` from the settings and the system: accent, appearance, accessibility. Reduce Motion cuts every flight.
    mutating func resolveLook() {
        look = settings.resolvedLook(systemAccent: systemAccent, dark: systemDark)
        look.reduceMotion = accessibility.reduceMotion
        look.reduceTransparency = accessibility.reduceTransparency
        look.increaseContrast = accessibility.increaseContrast
        animator.enabled = settings.animationEnabled && !accessibility.reduceMotion
    }

    mutating func settingsChanged(from old: Settings) {
        resolveLook()
        animator.curve = settings.animationCurve
        animator.duration = settings.flightDuration
        retileAll() // gaps or orientation may have changed
        if isOverview, settings.initialZoom != old.initialZoom { // the zoomed-out level is seen best by going there
            animator.fly(to: overviewOpeningCamera, now: now)
        }
    }

    // MARK: Reading

    public var deskCenter: CGPoint { MielCore.deskCenter(screens) }
    public var camera: Camera { animator.camera }
    public var transition: Double { animator.transition }

    public var activeScreen: ScreenInfo {
        if let id = activeScreenID, let s = screens.first(where: { $0.id == id }) { return s }
        if let f = focused, let w = window(f), let s = screenShowingMost(deskFrame(w), of: screens) { return s }
        return screens.first ?? ScreenInfo(id: 0, name: "", frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                           visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 875), scale: 2)
    }

    public func window(_ id: WindowID) -> ManagedWindow? { windows.first { $0.id == id } }
    func index(_ id: WindowID?) -> Int? { id.flatMap { id in windows.firstIndex { $0.id == id } } }

    /// Windows search, arrows, tidy-up and the minimap work on.
    var candidates: [ManagedWindow] { windows.filter { $0.isShown && $0.pinned == nil } }

    func deskFrame(_ w: ManagedWindow) -> CGRect {
        w.pinned ?? deskCamera.toDesk(w.frame, deskCenter: deskCenter)
    }

    /// True when the screens show all of it at rest.
    func isFullyVisible(_ w: ManagedWindow) -> Bool {
        let d = deskFrame(w)
        return !w.parked && visibleArea(d, on: screens) >= d.width * d.height - 1
    }

    var overviewContext: OverviewContext {
        OverviewContext(candidates: candidates.map { SearchCandidate(id: $0.id, title: $0.title, appName: $0.appName, bundleID: $0.bundleID) },
                        mru: mru.order, focused: isOverview ? (selection ?? focused) : focused, rows: look.paletteRows)
    }

    var hudShown: Bool { isOverview && overview.isOpen && settings.navigatorEnabled }

    // MARK: Cameras

    func roundedAtRest(_ c: Camera) -> Camera {
        let d = deskCenter
        return Camera(center: CGPoint(x: d.x + (c.center.x - d.x).rounded(), y: d.y + (c.center.y - d.y).rounded()), zoom: 1)
    }

    /// `camera` zoomed to `zoom` around a desk point, which stays put.
    func zoomed(_ camera: Camera, at deskPoint: CGPoint, to zoom: CGFloat) -> Camera {
        self.camera(showing: camera.toCanvas(deskPoint, deskCenter: deskCenter), at: deskPoint,
                    zoom: min(max(zoom, settings.minZoom), settings.maxZoom))
    }

    /// The camera that shows canvas point `p` at desk point `anchor`.
    func camera(showing p: CGPoint, at anchor: CGPoint, zoom: CGFloat) -> Camera {
        Camera(center: CGPoint(x: p.x - (anchor.x - deskCenter.x) / zoom, y: p.y - (anchor.y - deskCenter.y) / zoom), zoom: zoom)
    }

    /// The camera that shows `frame` at 100% on the active screen. An
    /// oversized window keeps its top-left corner on screen, where title bars live.
    func camera(for frame: CGRect) -> Camera {
        let v = activeScreen.visibleFrame
        var target = frame.center
        if frame.width > v.width { target.x = frame.minX + v.width / 2 }
        if frame.height > v.height { target.y = frame.minY + v.height / 2 }
        return roundedAtRest(camera(showing: target, at: v.center, zoom: 1))
    }

    // MARK: Overview cameras

    static let overviewMargin: CGFloat = 32 // free area to the screen's sides and to the palette and hints
    static let labelRoom: CGFloat = 36 // above a workspace for its number pill, below a window for its name

    /// The part of `screen` the zoomed-out canvas has to itself, in
    /// screen-local points: below the search field (or the result list while
    /// it shows), above the key hints, a margin in from the sides.
    func overviewFreeArea(on screen: ScreenInfo) -> CGRect {
        let size = screen.frame.size, m = Self.overviewMargin
        var top = m, bottom = size.height - m
        if hudShown, screen.id == activeScreen.id {
            let l = look
            let topInset = max(screen.safeAreaTop, screen.visibleFrame.minY - screen.frame.minY)
            let bottomInset = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
            top = PaletteMetrics.top(l, screenHeight: size.height, topInset: topInset)
                + PaletteMetrics.height(l, rows: paletteRowsShown, footer: paletteFooterShown) * l.hudScale + m
            bottom = size.height - PaletteMetrics.hintsMargin(l, bottomInset: bottomInset) - PaletteMetrics.hintsHeight(l) - m
        }
        return CGRect(x: m, y: top, width: max(1, size.width - m * 2), height: max(1, bottom - top))
    }

    /// Result rows the palette shows now (0: just the field), as the HUD draws them.
    var paletteRowsShown: Int {
        guard overview.listVisible, !overview.helpOpen else { return 0 }
        return max(1, min(overview.results.count - overview.listOffset, max(1, look.paletteRows)))
    }

    var paletteFooterShown: Bool {
        paletteRowsShown > 0 && overview.results.count > overview.listOffset + max(1, look.paletteRows)
    }

    /// Where `rect` (canvas) appears on `screen` with `camera`, through the
    /// lens of the full overview: its bounds in screen-local points.
    func lensedBounds(_ rect: CGRect, camera c: Camera, on screen: ScreenInfo) -> CGRect {
        var bounds = CGRect.null
        for i in 0 ... 4 { // straight edges bow under the lens; five points an edge find its extent
            let f = CGFloat(i) / 4
            for p in [CGPoint(x: rect.minX + rect.width * f, y: rect.minY), CGPoint(x: rect.minX + rect.width * f, y: rect.maxY),
                      CGPoint(x: rect.minX, y: rect.minY + rect.height * f), CGPoint(x: rect.maxX, y: rect.minY + rect.height * f)] {
                let d = c.toDesk(p, deskCenter: deskCenter)
                let q = lensScreenPoint(CGPoint(x: d.x - screen.frame.minX, y: d.y - screen.frame.minY), screenSize: screen.frame.size,
                                        look: look, transition: 1)
                bounds = bounds.union(CGRect(origin: q, size: .zero))
            }
        }
        return bounds
    }

    /// The camera that shows canvas point `p` at screen-local point `q` of `screen`, through the full lens.
    func camera(showing p: CGPoint, atScreenPoint q: CGPoint, on screen: ScreenInfo, zoom: CGFloat) -> Camera {
        let source = lensSourcePoint(q, screenSize: screen.frame.size, look: look, transition: 1)
        return camera(showing: p, at: CGPoint(x: source.x + screen.frame.minX, y: source.y + screen.frame.minY), zoom: zoom)
    }

    /// The camera that shows `rect` whole and centered in `area` (the free
    /// area by default) on the active screen, as seen through the lens, at
    /// `maxZoom` or the largest zoom below it that fits.
    func camera(fitting rect: CGRect, in area: CGRect? = nil, maxZoom: CGFloat) -> Camera {
        let screen = activeScreen, area = area ?? overviewFreeArea(on: screen)
        func centered(_ zoom: CGFloat) -> (camera: Camera, bounds: CGRect) {
            // The lens is not symmetric about the area's center: nudge the anchor until the drawn bounds are centered.
            var anchor = area.center, c = camera(showing: rect.center, atScreenPoint: anchor, on: screen, zoom: zoom)
            var bounds = lensedBounds(rect, camera: c, on: screen)
            for _ in 0 ..< 4 {
                anchor.x += area.midX - bounds.midX
                anchor.y += area.midY - bounds.midY
                c = camera(showing: rect.center, atScreenPoint: anchor, on: screen, zoom: zoom)
                bounds = lensedBounds(rect, camera: c, on: screen)
            }
            return (c, bounds)
        }
        func fits(_ b: CGRect) -> Bool { b.width <= area.width + 0.5 && b.height <= area.height + 0.5 }
        let high = min(max(maxZoom, settings.minZoom), settings.maxZoom)
        let best = centered(high)
        if fits(best.bounds) || high <= settings.minZoom { return best.camera }
        var lo = settings.minZoom, hi = high
        for _ in 0 ..< 24 { // bisect in log space for the largest zoom that fits
            let mid = exp((log(lo) + log(hi)) / 2)
            if fits(centered(mid).bounds) { lo = mid } else { hi = mid }
        }
        return centered(lo).camera
    }

    /// The free area less room above and below for the labels the overview draws there.
    var framingArea: CGRect {
        let a = overviewFreeArea(on: activeScreen)
        return a.insetBy(dx: 0, dy: min(Self.labelRoom, a.height / 4))
    }

    /// The camera that shows workspace `slot` whole and centered in the free area, its number pill included.
    func camera(framingWorkspace slot: Int, maxZoom: CGFloat) -> Camera {
        camera(fitting: workspaceFrame(slot), in: framingArea, maxZoom: maxZoom)
    }

    /// Where the overview opens: what the active screen showed at 100%
    /// (its workspace, when it rests on one), whole and centered in the free area.
    var overviewOpeningCamera: Camera {
        if let rest = restingSlot(deskCamera), rest.screen.id == activeScreen.id {
            return camera(framingWorkspace: rest.slot, maxZoom: settings.initialZoom)
        }
        return camera(fitting: deskCamera.toCanvas(activeScreen.frame, deskCenter: deskCenter), maxZoom: settings.initialZoom)
    }

    // MARK: Laying out the real windows

    /// Where the window really goes for `deskCamera`: on screen if any of it
    /// shows (kept below the menu bar), else a park slot.
    func desiredFrame(_ w: ManagedWindow) -> (frame: CGRect, parked: Bool) {
        if let pin = w.pinned { return (pin, false) }
        var d = deskCamera.toDesk(w.frame, deskCenter: deskCenter)
        if visibleArea(d, on: screens) > 0 {
            if let s = screenShowingMost(d, of: screens), d.minY < s.visibleFrame.minY,
               !screens.contains(where: { $0.id != s.id && $0.frame.contains(CGPoint(x: d.midX, y: d.minY)) }) {
                d.origin.y = s.visibleFrame.minY // macOS would push it there anyway
            }
            return (d.roundedFrame, false)
        }
        guard let screen = nearestScreen(to: d.center, of: screens) else { return (w.real, false) }
        return (parkSlot(size: w.frame.size, on: screen, corner: parkCorner(for: screen, among: screens)).roundedFrame, true)
    }

    /// Sends the real windows where the canvas says they are. Only what
    /// differs moves. `force` compares with the reported frames, ignoring
    /// moves still in flight.
    mutating func sync(_ ids: Set<WindowID>? = nil, force: Bool = false) {
        for i in windows.indices where windows[i].isShown && (ids?.contains(windows[i].id) ?? true) {
            let (desired, parked) = desiredFrame(windows[i])
            if parked != windows[i].parked {
                windows[i].reparks = 0
                layoutRevision += 1 // the crash watcher needs to know what is parked
            }
            windows[i].parked = parked
            let current = force ? windows[i].real : (windows[i].expected?.frame ?? windows[i].real)
            if !desired.isClose(to: current, tolerance: 0.5) { setFrame(i, desired) }
        }
    }

    mutating func setFrame(_ i: Int, _ frame: CGRect) {
        guard !windows[i].isFullScreen else { return } // moving it mid-transition makes macOS replay the Space slide
        windows[i].expected = Expectation(frame: frame, deadline: now + Self.expectationLifetime)
        windows[i].pending = nil
        outbox.append(.setFrame(windows[i].id, frame))
    }

    mutating func raise(_ i: Int) {
        windows.append(windows.remove(at: i))
    }

    mutating func showToast(_ text: String) {
        toast = text
        toastUntil = now + Self.toastDuration
    }
}

extension CGRect {
    var roundedFrame: CGRect {
        CGRect(x: minX.rounded(), y: minY.rounded(), width: width.rounded(), height: height.rounded())
    }
}
