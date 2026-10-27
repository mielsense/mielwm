import CoreGraphics
import MielCore

public enum GesturePhase: Sendable, Equatable {
    case began, changed, ended
}

public struct KeyPress: Sendable, Equatable {
    public var keyCode: UInt16
    public var modifiers: Modifiers
    var isRepeat: Bool
    /// What the key types with the current layout and modifiers.
    public var characters: String

    public init(keyCode: UInt16, modifiers: Modifiers, isRepeat: Bool = false, characters: String = "") {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isRepeat = isRepeat
        self.characters = characters
    }
}

/// Delivered on the main queue. Points are global, y-down.
public enum TapEvent: Sendable, Equatable {
    case action(Action, isRepeat: Bool)
    /// Key-capture mode: every unbound key. Switcher: Esc.
    case key(KeyPress)
    /// Modifier changes while the switcher is up (releasing ⌥ commits), or
    /// always with `reportsModifiers`.
    case modifiers(Modifiers)
    case pan(GesturePhase, CGPoint) // middle-button drag
    case move(GesturePhase, CGPoint) // move modifiers + left drag
    case resize(GesturePhase, CGPoint) // move modifiers + right drag
    case zoom(lines: Double, at: CGPoint) // zoom modifiers + wheel; positive = wheel up
    case magnify(Double, at: CGPoint) // pinch, only while the overview is open
}

/// Everything the tap callback reads. Set from the main thread.
public struct TapState: Equatable, Sendable {
    public var table = BindingTable()
    /// Overview fallback: consume every key the table does not bind and
    /// report it as `.key`.
    public var keyCapture = false
    /// The ⌥Tab strip is up: report modifier changes and Esc.
    public var switcher = false
    /// Pinch zooms only while the overview is open.
    public var overviewOpen = false
    /// Report every modifier change (the app warms captures on ⌃⌥ down).
    public var reportsModifiers = false
    /// Points a middle press travels before it pans instead of clicking.
    public var dragThreshold: Double = 10
    public var moveModifiers: Modifiers = [.control, .option]
    var zoomModifiers: Modifiers = [.control, .option] // ⌃ alone is macOS's Accessibility Zoom gesture

    public init() {}
}
