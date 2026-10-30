// Shared types. Core, Render, System and the app all code against these, so
// change them only together with every user.
//
// Geometry convention everywhere: points, y grows downward, origin at the
// top-left of the primary display (the Quartz / Accessibility convention).
// The canvas uses the same units and orientation and has no bounds.

import CoreGraphics
import CoreVideo
import Foundation

// MARK: - Identity and the system's view of windows

/// A window as macOS knows it: owning process plus CGWindowID.
public struct WindowID: Hashable, Codable, Sendable, CustomStringConvertible {
    public var pid: Int32
    public var number: UInt32

    public init(pid: Int32, number: UInt32) {
        self.pid = pid
        self.number = number
    }

    public var description: String { "\(pid):\(number)" }
}

public struct ScreenInfo: Hashable, Codable, Sendable {
    public var id: UInt32 // CGDirectDisplayID
    public var name: String
    public var frame: CGRect // global, y-down
    public var visibleFrame: CGRect // frame minus menu bar and Dock, global, y-down
    public var scale: CGFloat // backing scale factor
    public var safeAreaTop: CGFloat // notch height, 0 without one
    public var isBuiltIn: Bool

    public init(id: UInt32, name: String, frame: CGRect, visibleFrame: CGRect,
                scale: CGFloat, safeAreaTop: CGFloat = 0, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.scale = scale
        self.safeAreaTop = safeAreaTop
        self.isBuiltIn = isBuiltIn
    }
}

public struct WindowSnapshot: Hashable, Codable, Sendable {
    public var id: WindowID
    public var bundleID: String?
    public var appName: String
    public var title: String
    public var frame: CGRect // global, y-down
    public var isMinimized: Bool
    /// AXStandardWindow with a normal role. Dialogs, sheets, popovers and
    /// panels are false and stay unmanaged.
    public var isStandard: Bool
    public var isResizable: Bool
    public var isMovable: Bool
    /// In macOS full screen, in a Space of its own.
    public var isFullScreen: Bool

    public init(id: WindowID, bundleID: String?, appName: String, title: String, frame: CGRect,
                isMinimized: Bool = false, isStandard: Bool = true,
                isResizable: Bool = true, isMovable: Bool = true, isFullScreen: Bool = false) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.frame = frame
        self.isMinimized = isMinimized
        self.isStandard = isStandard
        self.isResizable = isResizable
        self.isMovable = isMovable
        self.isFullScreen = isFullScreen
    }
}

/// What System reports. Every move macOS tells us about arrives as
/// `windowFrameChanged`, including the ones we caused; telling them apart is
/// Core's job (see the reducer).
public enum SystemEvent: Sendable, Equatable {
    case windowAppeared(WindowSnapshot)
    case windowClosed(WindowID)
    case windowFrameChanged(WindowID, CGRect)
    case windowTitleChanged(WindowID, String)
    case windowMinimized(WindowID, Bool)
    /// Entered or left macOS full screen. Entering arrives before the
    /// screen-sized frame, leaving after the frame macOS put it back at.
    case windowFullScreen(WindowID, Bool)
    /// Focus from any source: our own commands, Cmd-Tab, the Dock, a click,
    /// an app raising itself.
    case windowFocused(WindowID)
    case appHidden(pid: Int32, Bool)
    case appTerminated(pid: Int32)
    case screensChanged([ScreenInfo])
}

/// What Core asks System to do. System runs these off the main thread, one
/// serial queue per app, and never blocks the caller.
public enum WindowCommand: Sendable, Equatable {
    /// Global frame. System applies size, position, size (so moves between
    /// displays of different sizes land right) and switches
    /// AXEnhancedUserInterface off around the change.
    case setFrame(WindowID, CGRect)
    /// Raise the window, make it main and key, activate its app.
    case focus(WindowID)
}

// MARK: - Live window images

public enum WindowFrame: @unchecked Sendable {
    case pixelBuffer(CVPixelBuffer) // live ScreenCaptureKit frame, IOSurface-backed
    case image(CGImage) // still, for parked windows
}

/// Implemented by System's capture manager, read by Render every frame.
public protocol WindowFrameSource: AnyObject, Sendable {
    /// The newest image of the window, nil if none yet.
    func latestFrame(for id: WindowID) -> WindowFrame?
    /// Bumps whenever `latestFrame` changes, so Render can skip re-uploads.
    func generation(for id: WindowID) -> UInt64
}

// MARK: - Camera and the canvas <-> desk mapping

/// One camera for all screens ("your screens are one desk"). `center` is the
/// canvas point shown at the center of the desk (the union of all screen
/// frames). At zoom 1 and center == desk center, canvas coordinates equal
/// global screen coordinates.
public struct Camera: Hashable, Codable, Sendable {
    public var center: CGPoint
    public var zoom: CGFloat

    public init(center: CGPoint, zoom: CGFloat = 1) {
        self.center = center
        self.zoom = zoom
    }

    public func toDesk(_ p: CGPoint, deskCenter: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - center.x) * zoom + deskCenter.x,
                y: (p.y - center.y) * zoom + deskCenter.y)
    }

    public func toCanvas(_ p: CGPoint, deskCenter: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - deskCenter.x) / zoom + center.x,
                y: (p.y - deskCenter.y) / zoom + center.y)
    }

    public func toDesk(_ r: CGRect, deskCenter: CGPoint) -> CGRect {
        let o = toDesk(r.origin, deskCenter: deskCenter)
        return CGRect(x: o.x, y: o.y, width: r.width * zoom, height: r.height * zoom)
    }

    public func toCanvas(_ r: CGRect, deskCenter: CGPoint) -> CGRect {
        let o = toCanvas(r.origin, deskCenter: deskCenter)
        return CGRect(x: o.x, y: o.y, width: r.width / zoom, height: r.height / zoom)
    }
}

public extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

// MARK: - Input vocabulary

public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let shift = Modifiers(rawValue: 1 << 0)
    public static let control = Modifiers(rawValue: 1 << 1)
    public static let option = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
}

public enum Direction: String, Codable, Sendable, CaseIterable {
    case left, right, up, down
}

/// Keys as the overview and switcher understand them. Typed text arrives
/// separately as `OverviewInput.text`, already translated by the input method.
public enum NamedKey: Hashable, Codable, Sendable {
    case arrow(Direction)
    case tab, enter, escape, f1
    case backspace // the key labeled "delete" on a Mac keyboard
    case forwardDelete // fn-delete
    case digit(Int) // 0...9, used with Control for "go to result n"
    case equals, minus
    case character(String) // a letter with a modifier held, e.g. Control-A
}

/// Bindable actions, also `mielwm <action>` on the command line.
public enum Action: Hashable, Codable, Sendable {
    case toggleOverview
    case search(String?)
    case tune
    case help
    case switchWindow(forward: Bool)
    case focus(Direction)
    case nudge(Direction)
    case pan(Direction)
    case zoomIn, zoomOut
    case fit, frame, summon, land, back
    case fill
    case fullscreen
    case pin
    case grow, shrink
    case arrange
    case undo, redo
    case refresh
    case noop
    // Layouts and workspaces (AeroSpace's model on the canvas)
    case layoutTiles // floating: tile it; stack: back to tiles; tiles: flip orientation
    case layoutStack // tiles: stack (AeroSpace's accordion); stack: back to tiles
    case toggleFloating // tiled ⇄ floating
    case workspace(Int) // 1...9: fly to that workspace
    case workspaceStep(forward: Bool) // next / previous workspace
    case moveToWorkspace(Int) // the window moves there and the camera follows
    case settings // opens the Settings window (handled by the app)
}

/// How a workspace lays out its windows. Floating windows belong to none.
public enum LayoutMode: String, Hashable, Codable, Sendable, CaseIterable {
    case tiles, stack, floating
}

/// Tiles side by side (horizontal) or above each other (vertical).
public enum TileOrientation: String, Hashable, Codable, Sendable, CaseIterable {
    case auto, horizontal, vertical
}

// MARK: - Look (the tunable appearance)

public struct RGB: Hashable, Codable, Sendable {
    public var r: Double, g: Double, b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    static let mielOrange = RGB(1.0, 0x6B / 255.0, 0x1A / 255.0) // #ff6b1a
}

public struct Look: Hashable, Codable, Sendable {
    // Lens (distortion.*)
    public var lensEnabled = true
    public var lensStrength = 0.14
    public var lensEdgeScale = 1.08
    public var lensFeather = 0.025
    public var lensTransitionPower = 1.0
    public var edgeBlur = 0.0
    public var edgeBlurStart = 0.45
    public var vignette = 0.0
    public var chromatic = 0.0

    // Canvas backdrop
    public var backgroundDim = 0.35
    public var gridEnabled = true
    public var gridSize = 80.0
    public var gridWidth = 1.0
    public var gridOpacity = 0.1
    public var gridDots = true
    public var gridDotSize = 2.5
    public var wallpaperEnabled = true
    public var blur = false
    public var blurStrength = 0.7
    public var parallaxEnabled = true
    public var parallaxStrength = 0.06
    public var parallaxDepth = 0.12

    // Windows on the map
    public var windowRounding = 10.0
    public var windowShadow = true
    public var labels = true
    public var dimUnmatched = 0.7

    // Minimap (canvas.minimap_*)
    public var minimapEnabled = true
    var minimapWidth = 240.0
    var minimapHeight = 150.0
    var minimapMargin = 24.0
    public var minimapOpacity = 0.8

    // HUD (navigator.*). Text is SF Pro at 12, 13, 14, 16, 18 or 24 pt times hudScale.
    public var accent = RGB.mielOrange
    var monoFont = "" // no longer drawn; kept so old configs load
    public var hudScale = 1.0
    public var paletteWidth = 680.0
    public var paletteTop = 0.1 // fraction of the screen height
    public var paletteRows = 6
    public var rowHeight = 44.0
    public var rounding = 8.0 // rows and pills; panels add 6
    public var panelOpacity = 0.8
    var uppercase = false // no longer drawn; kept so old configs load
    var letterSpacing = 0.0 // no longer drawn; kept so old configs load
    public var querySize = 24.0
    public var titleSize = 13.0
    public var detailSize = 12.0
    public var cornerSize = 12.0
    public var labelSize = 12.0
    var cornerLabels = false
    public var searchHeight = 56.0
    var searchBorder = 0.0 // no longer drawn; kept so old configs load
    var searchBorderOpacity = 0.85 // no longer drawn
    var searchBorderColor: RGB? = nil // no longer drawn
    var searchGlow = 0.0 // no longer drawn
    /// Dark or light chrome; the app follows the system appearance.
    public var dark = true
    /// The system's accessibility display options (the app sets them, nothing saves them):
    /// cut instead of flying, opaque panels, stronger edges.
    public var reduceMotion = false
    public var reduceTransparency = false
    public var increaseContrast = false

    public init() {}
}

/// macOS's accessibility display options that change how the overview looks and moves.
public struct AccessibilityOptions: Hashable, Sendable {
    public var reduceMotion = false
    public var reduceTransparency = false
    public var increaseContrast = false

    public init(reduceMotion: Bool = false, reduceTransparency: Bool = false, increaseContrast: Bool = false) {
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
    }
}

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
    public var alpha: Double

    public init(id: WindowID, canvasFrame: CGRect, title: String, appName: String,
                bundleID: String? = nil, dim: Double = 0, isSelected: Bool = false,
                isFocused: Bool = false, isPinned: Bool = false, alpha: Double = 1) {
        self.id = id
        self.canvasFrame = canvasFrame
        self.title = title
        self.appName = appName
        self.bundleID = bundleID
        self.dim = dim
        self.isSelected = isSelected
        self.isFocused = isFocused
        self.isPinned = isPinned
        self.alpha = alpha
    }
}

/// A workspace's frame on the canvas: the screen-sized area its tiles fill.
public struct SceneWorkspace: Hashable, Sendable {
    public var number: Int? // 1...9, nil past 9
    public var canvasFrame: CGRect
    public var mode: LayoutMode // .tiles or .stack
    public var isCurrent: Bool // the one the camera rests on (or last rested on)
    public var windowCount: Int
    /// Shown in an empty workspace, `{...}` as keycaps ("Workspace 4 is empty  {⌥⇧4} Move a window here").
    public var emptyMessage = ""

    public init(number: Int?, canvasFrame: CGRect, mode: LayoutMode, isCurrent: Bool = false, windowCount: Int = 0) {
        self.number = number
        self.canvasFrame = canvasFrame
        self.mode = mode
        self.isCurrent = isCurrent
        self.windowCount = windowCount
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
        a.title == b.title && a.entries.map(\.keys) == b.entries.map(\.keys)
            && a.entries.map(\.action) == b.entries.map(\.action)
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
    public var corners = ["", "", "", ""] // top-left, top-right, bottom-left, bottom-right
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
    public var time: Double // seconds, for the caret blink and small animations
    public var workspaces: [SceneWorkspace] = [] // drawn behind the windows, with the transition

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
