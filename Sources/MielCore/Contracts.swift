import CoreGraphics
import CoreVideo
import Foundation

// Shared types. Core, Render, System and the app all code against these, so
// change them only together with every user.
//
// Geometry convention everywhere: points, y grows downward, origin at the
// top-left of the primary display (the Quartz / Accessibility convention).
// The canvas uses the same units and orientation and has no bounds.

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
    public var topBar: TopBar? // a status bar under the menu bar, for the Automatic top gap

    public init(id: UInt32, name: String, frame: CGRect, visibleFrame: CGRect,
                scale: CGFloat, safeAreaTop: CGFloat = 0, isBuiltIn: Bool = false, topBar: TopBar? = nil) {
        self.id = id
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.scale = scale
        self.safeAreaTop = safeAreaTop
        self.isBuiltIn = isBuiltIn
        self.topBar = topBar
    }

    /// Room the notch or the menu bar takes at the top, and the Dock at the bottom, in points.
    public var topInset: CGFloat { max(safeAreaTop, visibleFrame.minY - frame.minY) }
    public var bottomInset: CGFloat { max(0, frame.maxY - visibleFrame.maxY) }
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
    /// What mielwm moves: standard windows that can move.
    public var isManageable: Bool { isStandard && isMovable }

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
    /// `dragging`: the left mouse button is down, or just came up at the end
    /// of a drag (see `isUserDrag`), so the user may be dragging it. Only then does a resize
    /// move the split with a neighbour tile.
    case windowFrameChanged(WindowID, CGRect, dragging: Bool = false)
    case windowTitleChanged(WindowID, String)
    case windowMinimized(WindowID, Bool)
    /// Entered or left macOS full screen. Entering arrives before the
    /// screen-sized frame, leaving after the frame macOS put it back at.
    case windowFullScreen(WindowID, Bool)
    /// Focus from any source: our own commands, Cmd-Tab, the Dock, a click,
    /// an app raising itself.
    case windowFocused(WindowID)
    /// Focus went to nothing mielwm manages: the desktop, a sheet or panel,
    /// an app it leaves alone. No managed window has focus now.
    case unmanagedFocus(pid: Int32)
    case appHidden(pid: Int32, Bool)
    case appTerminated(pid: Int32)
    case screensChanged([ScreenInfo])
}

/// Seconds after the left button comes up that frame reports still belong to
/// the user's drag: slow apps report its last steps late, some resize only on release.
let dragGrace = 0.5

/// Whether a frame report is part of a user drag (`windowFrameChanged`'s
/// `dragging`): the button is down, or it came up recently after a press that
/// dragged. Seconds since the last press, drag and release, from the same clock.
/// A plain click (a Dock icon, a double-click on a title bar) has no drag after
/// its press, so an app's own resize right after it is never taken for the user's.
public func isUserDrag(buttonDown: Bool, sinceMouseDown: Double, sinceDrag: Double, sinceMouseUp: Double) -> Bool {
    buttonDown || (sinceMouseUp < dragGrace && sinceDrag < sinceMouseDown)
}

/// What Core asks System to do. System runs these off the main thread, one
/// serial queue per app, and never blocks the caller.
public enum WindowCommand: Sendable, Equatable {
    /// Global frame. System sets the size, the position and the size again
    /// (so moves between displays of different sizes land right), or only the
    /// position when the size is the one it last set, and switches
    /// AXEnhancedUserInterface off around the change.
    case setFrame(WindowID, CGRect)
    /// Raise the window, make it main and key, activate its app.
    case focus(WindowID)
    /// Press the window's close button, as a click on it would.
    case close(WindowID)
    /// Minimize it to the Dock.
    case minimize(WindowID)
}

extension WindowCommand {
    var isFocus: Bool { if case .focus = self { true } else { false } }
}

// MARK: - Live window images

public enum WindowFrame: @unchecked Sendable {
    case pixelBuffer(CVPixelBuffer) // live ScreenCaptureKit frame, IOSurface-backed
    case image(CGImage) // still: parked windows, windows past the live stream limit, frames gone quiet
}

/// Implemented by System's capture manager, read by Render every frame.
public protocol WindowFrameSource: AnyObject, Sendable {
    /// The newest image of the window, nil if none yet.
    func latestFrame(for id: WindowID) -> WindowFrame?
    /// Bumps whenever `latestFrame` changes, so Render can skip re-uploads.
    func generation(for id: WindowID) -> UInt64
}
