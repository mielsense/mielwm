import AppKit
import MielCore
import SwiftUI

/// What the overview's chrome shows on one display: Core's HUD, the look,
/// and the display's size and insets in points.
struct ChromeContent: Equatable {
    var hud = HUDModel()
    var look = Look()
    var size = CGSize.zero
    var topInset: CGFloat = 0 // notch or menu bar
    var bottomInset: CGFloat = 0 // Dock
    var worldShown = true // the canvas is drawn behind; false: the live desktop (⌥Tab on its own)
}

@MainActor
final class ChromeModel: ObservableObject {
    @Published var content = ChromeContent()
}

/// The overview's floating chrome as native views over the Metal canvas, so
/// Liquid glass is Apple's own and bends the canvas behind it, not the text.
/// It takes no clicks, keys or scrolls: the canvas view below it handles
/// input exactly as before.
final class OverlayChrome: NSView {
    private let model = ChromeModel()
    /// The palette and the pills fade in with the zoom; the switcher and toasts show at once.
    private let eased: NSHostingView<EasedChrome>
    private let steady: NSHostingView<SteadyChrome>

    init() {
        eased = NSHostingView(rootView: EasedChrome(model: model))
        steady = NSHostingView(rootView: SteadyChrome(model: model))
        super.init(frame: .zero)
        wantsLayer = true
        for host in [eased, steady] as [NSView] {
            host.autoresizingMask = [.width, .height]
            host.frame = bounds
            addSubview(host)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// One frame of the overlay: the HUD for this display, faded with the camera's `transition` and the overlay's `opacity`.
    func show(_ content: ChromeContent, transition: Double, opacity: Double) {
        if model.content != content { model.content = content }
        let t = min(max(transition, 0), 1), ease = t * t * (3 - 2 * t) // smoothstep, as the Metal HUD faded
        set(eased, ease * opacity)
        set(steady, opacity)
    }

    /// Hidden: nothing stale shows for a frame when the overlay comes back.
    func clear() {
        if model.content.hud != HUDModel() { model.content.hud = HUDModel() }
    }

    private func set(_ view: NSView, _ alpha: Double) {
        if abs(view.alphaValue - alpha) > 0.001 { view.alphaValue = alpha }
    }
}
