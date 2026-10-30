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
    var toastOpacity = 1.0 // the toast fades out as its notice does
}

extension ChromeContent {
    /// The chrome for `scene`'s display, taking its HUD out of the scene, so a
    /// change only the chrome shows doesn't make Metal redraw the canvas.
    init(taking scene: inout MielCore.Scene, worldShown: Bool = true, toastOpacity: Double = 1) {
        let s = scene.screen
        self.init(hud: scene.hud, look: scene.look, size: s.frame.size, topInset: s.topInset, bottomInset: s.bottomInset,
                  worldShown: worldShown, toastOpacity: toastOpacity)
        scene.hud = HUDModel()
    }
}

/// The HUD's content for SwiftUI, set on each frame that changes it.
@MainActor
final class ChromeModel: ObservableObject {
    @Published var content: ChromeContent

    init(_ content: ChromeContent = ChromeContent()) { self.content = content }
}

/// The overview's floating chrome as native views over the Metal canvas, so
/// Liquid glass is Apple's own and bends the canvas behind it, not the text.
/// It takes no clicks, keys or scrolls: the canvas view below it handles input.
final class OverlayChrome: NSView {
    /// The palette and the pills fade in with the zoom; the switcher and toasts show at once.
    /// Each has its own model, so a toast or a new selection in the switcher leaves the palette alone.
    private let easedModel = ChromeModel(), steadyModel = ChromeModel()
    private let eased: NSHostingView<EasedChrome>
    private let steady: NSHostingView<SteadyChrome>

    init() {
        eased = NSHostingView(rootView: EasedChrome(model: easedModel))
        steady = NSHostingView(rootView: SteadyChrome(model: steadyModel))
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
        let (palette, rest) = Self.split(content)
        if easedModel.content != palette { easedModel.content = palette }
        if steadyModel.content != rest { steadyModel.content = rest }
        set(eased, Self.easedAlpha(transition) * opacity)
        set(steady, opacity)
    }

    /// What the eased layer (palette and pills) and the steady one (switcher and toast) each show.
    static func split(_ content: ChromeContent) -> (eased: ChromeContent, steady: ChromeContent) {
        var palette = content, rest = content
        palette.hud.toast = nil
        palette.toastOpacity = 1
        if content.hud.mode == .switcher { palette.hud.rows = [] }
        rest.hud = HUDModel()
        rest.hud.toast = content.hud.toast
        if content.hud.mode == .switcher { (rest.hud.mode, rest.hud.rows, rest.hud.selectedRow) = (.switcher, content.hud.rows, content.hud.selectedRow) }
        return (palette, rest)
    }

    /// The palette's fade with the zoom: smoothstep of the camera's transition.
    static func easedAlpha(_ transition: Double) -> Double {
        let t = min(max(transition, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Hidden: nothing stale shows for a frame when the overlay comes back.
    func clear() {
        for m in [easedModel, steadyModel] where m.content.hud != HUDModel() { m.content.hud = HUDModel() }
    }

    private func set(_ view: NSView, _ alpha: Double) {
        if abs(view.alphaValue - alpha) > 0.001 { view.alphaValue = alpha }
    }
}
