import CoreGraphics

/// The modifier keys held with a key or a click.
public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let shift = Modifiers(rawValue: 1 << 0)
    public static let control = Modifiers(rawValue: 1 << 1)
    public static let option = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
}

/// An arrow key's direction, for focus, nudge, pan and moving windows.
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
    case resize(ResizeAxis, Int) // AeroSpace's resize: points more (or fewer, below zero)
    case close, minimize // the window itself (its close button, the Dock)
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
    case workspaceBackAndForth // the workspace shown before this one
    case moveToWorkspace(Int) // the window moves there and the camera follows
    case settings // opens the Settings window (handled by the app)
}

/// Which side `resize` changes: along the tiles' split (smart), or one dimension.
public enum ResizeAxis: String, Hashable, Codable, Sendable, CaseIterable {
    case smart, width, height
}

/// How a workspace lays out its windows. Floating windows belong to none.
public enum LayoutMode: String, Hashable, Codable, Sendable, CaseIterable {
    case tiles, stack, floating
}

/// Tiles side by side (horizontal) or above each other (vertical).
public enum TileOrientation: String, Hashable, Codable, Sendable, CaseIterable {
    case auto, horizontal, vertical
}
