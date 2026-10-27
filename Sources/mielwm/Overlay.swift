import AppKit
import MielCore
import MielRender
import MielSystem
import QuartzCore

/// Borderless and see-through, so it can take the keyboard while the overview is open.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// One display's overlay: a transparent window above everything (menu bar
/// included) with a Metal layer, drawn on that display's own display link.
@MainActor
final class Overlay {
    let screenID: UInt32
    let window: OverlayWindow
    let view: OverlayView

    init(screenID: UInt32, controller: Controller, device: MTLDevice) {
        self.screenID = screenID
        window = OverlayWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        view = OverlayView(screenID: screenID, controller: controller, device: device)
        window.isOpaque = false // non-opaque, so macOS does not treat the windows below as hidden
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.animationBehavior = .none
        window.contentView = view
    }

    func place(on screen: ScreenInfo) {
        guard let ns = NSScreen.screens.first(where: { $0.displayID == screen.id }) else { return }
        window.setFrame(ns.frame, display: false)
        view.metal.contentsScale = ns.backingScaleFactor
        view.resize()
    }

    func show(key: Bool) {
        if key {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
        } else {
            window.orderFrontRegardless()
        }
        view.link?.isPaused = false
    }

    func hide() {
        view.link?.isPaused = true
        view.showCaret(nil)
        window.orderOut(nil)
    }

    /// Hidden for a while: a fresh layer, so the old one's drawables (full-screen surfaces) go.
    func dropDrawables() {
        view.makeLayer(device: view.metal.device)
    }

    func close() {
        view.link?.invalidate()
        window.orderOut(nil)
    }

    func draw(_ scene: Scene, renderer: Renderer, frames: WindowFrameSource) {
        guard renderer.needsDraw(scene, frames: frames), let drawable = view.metal.nextDrawable() else { return }
        renderer.draw(scene, frames: frames, into: drawable)
        view.showCaret(renderer.caret(screenID: screenID))
    }
}

final class OverlayView: NSView, NSTextInputClient {
    let screenID: UInt32
    private(set) var metal = CAMetalLayer()
    private let caret = CALayer()
    var link: CADisplayLink?
    private weak var controller: Controller?
    private var marked = ""

    init(screenID: UInt32, controller: Controller, device: MTLDevice) {
        self.screenID = screenID
        self.controller = controller
        super.init(frame: .zero)
        makeLayer(device: device)
        wantsLayer = true
    }

    func makeLayer(device: MTLDevice?) {
        let scale = metal.contentsScale
        metal = CAMetalLayer()
        metal.device = device
        metal.pixelFormat = Renderer.pixelFormat
        metal.isOpaque = false
        metal.framebufferOnly = true
        metal.maximumDrawableCount = 3
        metal.contentsScale = scale
        metal.frame = bounds
        metal.addSublayer(caret)
        layer = metal // layer-hosting: we size and scale it ourselves
        resize()
    }

    /// The search field's caret, blinked by Core Animation like the system's, so an
    /// idle field costs no frames; it restarts on (solid while typing) when it moves.
    func showCaret(_ c: (rect: CGRect, alpha: Double, color: SIMD4<Float>)?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        caret.isHidden = c == nil
        guard let c else { return }
        let s = metal.contentsScale
        let frame = CGRect(x: c.rect.minX / s, y: c.rect.minY / s, width: c.rect.width / s, height: c.rect.height / s) // the flipped view flips its layer too
        let space = window?.screen?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)! // the frames are not color matched
        caret.backgroundColor = CGColor(colorSpace: space, components: [CGFloat(c.color.x), CGFloat(c.color.y), CGFloat(c.color.z), CGFloat(c.alpha)])
        guard caret.frame != frame || caret.animation(forKey: "blink") == nil else { return }
        caret.frame = frame
        caret.add(Self.blink, forKey: "blink")
    }

    /// On, a quick fade out, off, a fade back in: the caret the renderer draws in snapshots.
    private static let blink: CAKeyframeAnimation = {
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = [1, 1, 0, 0, 1]
        a.keyTimes = [0, 0.42, 0.5, 0.92, 1]
        let linear = CAMediaTimingFunction(name: .linear), ease = CAMediaTimingFunction(name: .easeInEaseOut)
        a.timingFunctions = [linear, ease, linear, ease]
        a.duration = 1.06
        a.repeatCount = .infinity
        return a
    }()

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true } // y down, like everything in mielwm
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, link == nil else { return }
        let link = displayLink(target: self, selector: #selector(step))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120) // ProMotion
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    override func setFrameSize(_ size: NSSize) {
        super.setFrameSize(size)
        resize()
    }

    func resize() {
        metal.drawableSize = CGSize(width: bounds.width * metal.contentsScale, height: bounds.height * metal.contentsScale)
    }

    @objc private func step(_ link: CADisplayLink) {
        controller?.frame(screenID: screenID)
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        guard let controller else { return }
        let mods = EventTap.modifiers(event.cgEvent?.flags ?? [])
        if marked.isEmpty, let key = Controller.namedKey(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? "",
                                                         modifiers: mods) {
            return controller.input(.key(key, mods))
        }
        if mods.contains(.command) || mods.contains(.control) { return } // chords that mean nothing here
        interpretKeyEvents([event]) // layouts, dead keys and input methods
    }

    override func doCommand(by selector: Selector) {} // no beep for keys the input method does not type

    func insertText(_ string: Any, replacementRange: NSRange) {
        marked = ""
        let text = (string as? NSAttributedString)?.string ?? string as? String ?? ""
        if !text.isEmpty { controller?.input(.text(text)) }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        marked = (string as? NSAttributedString)?.string ?? string as? String ?? ""
        controller?.input(.markedText(marked))
    }

    func unmarkText() {
        marked = ""
        controller?.input(.markedText(""))
    }

    func hasMarkedText() -> Bool { !marked.isEmpty }
    func markedRange() -> NSRange { marked.isEmpty ? NSRange(location: NSNotFound, length: 0) : NSRange(location: 0, length: marked.utf16.count) }
    func selectedRange() -> NSRange { NSRange(location: marked.utf16.count, length: 0) }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func characterIndex(for point: NSPoint) -> Int { NSNotFound }

    /// Where input method windows appear: the search field near the top.
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window, let look = controller?.state.look else { return .zero }
        let field = NSRect(x: bounds.midX - 200, y: bounds.height * look.paletteTop, width: 400, height: look.searchHeight * look.hudScale)
        return window.convertToScreen(convert(field, to: nil))
    }

    // MARK: Mouse

    private func local(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func mouseDown(with event: NSEvent) { controller?.overlayMouseDown(local(event), screenID: screenID) }
    override func mouseDragged(with event: NSEvent) { controller?.overlayMouseDragged(local(event)) }
    override func mouseUp(with event: NSEvent) { controller?.overlayMouseUp(local(event)) }
    override func mouseMoved(with event: NSEvent) { controller?.overlayMouseMoved(local(event), screenID: screenID) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if trackingAreas.isEmpty { // one for the view's lifetime; inVisibleRect keeps it sized
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = CGVector(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
        guard delta.dx != 0 || delta.dy != 0 else { return }
        controller?.overlayScroll(local(event), screenID: screenID, delta: delta, precise: event.hasPreciseScrollingDeltas,
                                  zoom: !event.modifierFlags.isDisjoint(with: [.command, .control]))
    }

    /// Pinch. Normally the event tap takes it first; this covers running without the tap.
    override func magnify(with event: NSEvent) {
        controller?.overlayMagnify(local(event), screenID: screenID, magnification: event.magnification)
    }
}
