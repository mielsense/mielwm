import AppKit
import MielCore
import MielSystem

/// Above normal windows and below the overview's overlay; it never takes
/// focus or the mouse. mielwm tracks and captures only other apps' windows,
/// so it never sees this one.
final class NoticeWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// One notice on screen: a borderless panel holding the material and the drawing.
@MainActor
final class NoticePanel {
    /// What it last drew, so a tick that only fades it redraws nothing.
    struct Drawn: Equatable {
        var content: NoticeContent
        var screenID: UInt32
        var accent: RGB
        var increaseContrast: Bool
        var material: Design.ChromeMaterial
    }

    let window: NoticeWindow
    var drawn: Drawn?
    private let canvas = NoticeCanvas()
    private var built: (material: Design.ChromeMaterial, radius: CGFloat, increaseContrast: Bool)?

    init() {
        window = NoticeWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
    }

    /// Draws `drawing` centred on `x` with its top edge at `top`, in AppKit points (y up).
    func show(_ drawing: NoticeDrawing, center x: CGFloat, top: CGFloat, material: Design.ChromeMaterial, increaseContrast: Bool) {
        if built?.material != material || built?.radius != drawing.radius || built?.increaseContrast != increaseContrast {
            build(material, radius: drawing.radius, increaseContrast: increaseContrast)
        }
        canvas.drawing = drawing
        let frame = NSRect(x: (x - drawing.size.width / 2).rounded(), y: (top - drawing.size.height).rounded(),
                           width: drawing.size.width, height: drawing.size.height)
        if window.frame != frame { window.setFrame(frame, display: false) }
        canvas.needsDisplay = true
        if !window.isVisible { window.orderFrontRegardless() }
        window.invalidateShadow()
    }

    func hide() {
        drawn = nil
        if window.isVisible { window.orderOut(nil) }
    }

    private func build(_ material: Design.ChromeMaterial, radius: CGFloat, increaseContrast: Bool) {
        built = (material, radius, increaseContrast)
        canvas.radius = radius
        canvas.edge = increaseContrast ? .contrast : material == .glass ? .none : .light
        canvas.solid = material == .solid
        canvas.removeFromSuperview()
        canvas.autoresizingMask = [.width, .height]
        window.hasShadow = material != .glass // glass draws its own
        if material == .glass, #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = radius
            glass.contentView = canvas
            window.contentView = glass
        } else if material == .solid {
            window.contentView = canvas
        } else {
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.maskImage = capsuleMask(radius)
            canvas.frame = effect.bounds
            effect.addSubview(canvas)
            window.contentView = effect
        }
    }

    /// A stretchable rounded mask, for the material's corners.
    private func capsuleMask(_ radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { r in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// The drawing, with an edge: light catching the top of the material, or a
/// solid line with Increase Contrast.
final class NoticeCanvas: NSView {
    enum Edge { case none, light, contrast }

    var drawing: NoticeDrawing?
    var radius: CGFloat = 0
    var edge = Edge.light
    var solid = false

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        if solid {
            NSColor.windowBackgroundColor.setFill()
            outline.fill()
        }
        MainActor.assumeIsolated { drawing?.draw(bounds) }
        let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5)
        ring.lineWidth = 1
        switch edge {
        case .none: break
        case .contrast:
            NSColor.labelColor.withAlphaComponent(0.6).setStroke()
            ring.stroke()
        case .light:
            // Brighter along the top, as if lit from above; faint at the bottom.
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            NSGraphicsContext.saveGraphicsState()
            let band = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
            band.append(NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: radius - 1, yRadius: radius - 1).reversed)
            band.addClip()
            NSGradient(starting: NSColor.white.withAlphaComponent(dark ? 0.28 : 0.7),
                       ending: (dark ? NSColor.white : NSColor.black).withAlphaComponent(dark ? 0.06 : 0.08))?.draw(in: bounds, angle: 90)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

/// Keeps the panels in step with Core's notices, and speaks what changed to VoiceOver.
@MainActor
final class NoticeBoard {
    private let toast = NoticePanel(), workspace = NoticePanel(), stack = NoticePanel()
    private var spokenWorkspace: Notice<WorkspaceNotice>?
    private var spokenSwitcher: String?
    private var spokenOverview: String?
    private var spokenToast: Notice<String>?

    func update(_ state: CanvasState) {
        defer { speak(state) }
        // The overview has its own toasts, and its overlay would cover these anyway; hidden, they don't tick under it.
        guard !state.isOverview else { return hideAll() }
        let n = state.notices
        place(toast, n.toastInOverview ? nil : n.toast, NoticeContent.toast, state) { _, f, _, s in
            (f.midX, f.maxY - f.height * Notices.toastCenter + s.height / 2)
        }
        place(workspace, state.workspacePill, NoticeContent.workspace, state) { _, f, visible, s in
            (f.midX, visible.minY + 20 + s.height) // just above the Dock
        }
        place(stack, n.stack, NoticeContent.stack, state) { strip, _, _, _ in
            let top = Displays.toYDown(strip.area, primaryHeight: NSScreen.screens.first?.frame.height ?? 0).maxY
            return (strip.area.midX, top - 10) // just inside the stack's top edge
        }
    }

    func hideAll() {
        for p in [toast, workspace, stack] { p.hide() }
    }

    /// Shows `notice` at `position(content, screen frame, visible frame, size)`, or hides the panel.
    private func place<C>(_ panel: NoticePanel, _ notice: Notice<C>?, _ wrap: (C) -> NoticeContent, _ state: CanvasState,
                          at position: (C, NSRect, NSRect, CGSize) -> (x: CGFloat, top: CGFloat)) {
        let opacity = notice?.opacity(at: state.now) ?? 0
        guard let notice, opacity > 0, let screen = NSScreen.screens.first(where: { $0.displayID == notice.screenID }) else {
            return panel.hide()
        }
        let a = state.accessibility
        let key = NoticePanel.Drawn(content: wrap(notice.content), screenID: notice.screenID, accent: state.look.accent,
                                    increaseContrast: a.increaseContrast, material: Design.ChromeMaterial.current(state.look))
        if panel.drawn != key {
            let drawing = noticeDrawing(key.content, accent: key.accent, increaseContrast: key.increaseContrast, maxWidth: screen.visibleFrame.width - 48)
            let p = position(notice.content, screen.frame, screen.visibleFrame, drawing.size)
            panel.show(drawing, center: p.x, top: p.top, material: key.material, increaseContrast: key.increaseContrast)
            panel.drawn = key
        }
        panel.window.alphaValue = opacity
    }

    private func speak(_ state: CanvasState) {
        guard state.notices.workspace != nil || state.notices.toast != nil || state.overview.switcher || state.isOverview || spokenOverview != nil,
              NSWorkspace.shared.isVoiceOverEnabled else { return }
        if let w = state.notices.workspace, w != spokenWorkspace {
            spokenWorkspace = w
            announce(w.content.spoken)
        }
        if let t = state.notices.toast, t != spokenToast {
            spokenToast = t
            announce(hintSegments(t.content).map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")) // "Tidied 4 windows ⌘Z Undo"
        }
        let overview = state.overviewSpeech
        if overview != spokenOverview {
            spokenOverview = overview
            if let overview { announce(overview) }
        }
        let app = state.switcherSpeech, switcher = app.map { "\(state.overview.selected) \($0)" }
        if switcher != spokenSwitcher {
            spokenSwitcher = switcher
            if let app { announce(app) }
        }
    }

    private func announce(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
