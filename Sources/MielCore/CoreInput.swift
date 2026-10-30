import CoreGraphics

/// Pointer gestures the app forwards, in desk points.
public enum PointerGesture: Hashable, Sendable {
    case pan(CGVector) // the pointer moved this far; the canvas follows it
    case panEnded(velocity: CGVector) // points per second at release, for momentum
    case zoom(at: CGPoint, factor: CGFloat) // wheel: exp(±zoomStep), a short glide
    case pinch(at: CGPoint, factor: CGFloat) // 1 + magnification (or a precise ⌘-scroll): follows the fingers, no glide
    case dragWindow(WindowID, CGVector)
    case resizeWindow(WindowID, Corner, CGVector)
    case dragEnded(WindowID)
    case minimapJump(CGPoint) // canvas point to center on

    public enum Corner: Hashable, Sendable { case topLeft, topRight, bottomLeft, bottomRight }
}

/// Everything that can happen to the canvas, one at a time, for `CanvasState.send(_:)`.
public enum CoreInput: Equatable, Sendable {
    case system(SystemEvent)
    case action(Action)
    case key(NamedKey, Modifiers) // while the overview or the switcher has the keyboard
    case text(String)
    case markedText(String)
    case modifiersChanged(Modifiers) // releasing ⌥ ends the switcher
    case gesture(PointerGesture)
    case tick(Double) // seconds on a monotonic clock
    case select(WindowID) // hover or click selection in the overview, camera stays
    case landOn(WindowID) // click a window in the overview
    case unparkAll // quit, toggle off, signals: every window back on a screen
    case setSettings(Settings) // config reloaded
}
