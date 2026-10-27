import AppKit
import MielCore
import MielRender
import MielSystem
import QuartzCore

extension Controller {
    func overlayMouseDown(_ p: CGPoint, screenID: UInt32) {
        mouse = nil
        guard state.settings.pointer, let screen = screen(id: screenID) else { return }
        if state.look.minimapEnabled, let hit = state.minimapLayout(for: screen).hit(p) {
            switch hit {
            case .arrange: input(.action(.arrange))
            case let .jump(c): input(.gesture(.minimapJump(c)))
            }
            return
        }
        mouse = (p, p, state.window(atScreenPoint: p, on: screen), state.canvasPoint(atScreenPoint: p, on: screen), false, screen)
    }

    func overlayMouseDragged(_ p: CGPoint) {
        guard var m = mouse else { return }
        if !m.dragging, hypot(p.x - m.start.x, p.y - m.start.y) > state.settings.dragThreshold {
            m.dragging = true
            panSamples = []
        }
        if m.dragging {
            let now = CACurrentMediaTime()
            let zoom = state.camera.zoom
            let here = state.canvasPoint(atScreenPoint: p, on: m.screen)
            if let id = m.window {
                // Through the lens: the window stays under the pointer even near the edges.
                let before = state.canvasPoint(atScreenPoint: m.last, on: m.screen)
                input(.gesture(.dragWindow(id, CGVector(dx: (here.x - before.x) * zoom, dy: (here.y - before.y) * zoom))))
            } else {
                // The grabbed canvas point stays under the pointer.
                let k = zoom / max(state.settings.panSensitivity, 0.01)
                input(.gesture(.pan(CGVector(dx: (here.x - m.grab.x) * k, dy: (here.y - m.grab.y) * k))))
                panSamples.append((now, CGVector(dx: p.x - m.last.x, dy: p.y - m.last.y)))
            }
        }
        m.last = p
        mouse = m
    }

    /// Hover picks the window under the pointer, as in Mission Control; the camera stays.
    func overlayMouseMoved(_ p: CGPoint, screenID: UInt32) {
        guard state.settings.pointer, mouse == nil, let screen = screen(id: screenID), let id = state.window(atScreenPoint: p, on: screen),
              id != state.selection else { return }
        input(.select(id))
    }

    func overlayMouseUp(_ p: CGPoint) {
        guard let m = mouse else { return }
        mouse = nil
        if !m.dragging {
            if let id = m.window { input(.landOn(id)) }
        } else if let id = m.window {
            input(.gesture(.dragEnded(id)))
        } else {
            input(.gesture(.panEnded(velocity: velocity(CACurrentMediaTime()))))
        }
    }

    /// Trackpad scrolling pans, the canvas following the fingers 1:1 where
    /// the pointer is (momentum included: macOS sends it as more scrolling).
    /// A mouse wheel, or ⌘ or ⌃ held, zooms around the pointer.
    func overlayScroll(_ p: CGPoint, screenID: UInt32, delta: CGVector, precise: Bool, zoom: Bool) {
        guard state.settings.pointer, let screen = screen(id: screenID) else { return }
        let desk = state.deskPoint(atScreenPoint: p, on: screen)
        if precise, !zoom {
            let a = state.canvasPoint(atScreenPoint: p, on: screen)
            let b = state.canvasPoint(atScreenPoint: CGPoint(x: p.x + delta.dx, y: p.y + delta.dy), on: screen)
            let k = state.camera.zoom / max(state.settings.panSensitivity, 0.01)
            return input(.gesture(.pan(CGVector(dx: (b.x - a.x) * k, dy: (b.y - a.y) * k))))
        }
        // Wheels move in lines; trackpads in points, about ten to a line.
        if precise { return input(.gesture(.pinch(at: desk, factor: zoomFactor(lines: delta.dy / 10)))) }
        if delta.dy != 0 { input(.gesture(.zoom(at: desk, factor: zoomFactor(lines: delta.dy)))) }
    }

    func overlayMagnify(_ p: CGPoint, screenID: UInt32, magnification: Double) {
        guard state.settings.pointer, let screen = screen(id: screenID) else { return }
        input(.gesture(.pinch(at: state.deskPoint(atScreenPoint: p, on: screen), factor: 1 + magnification)))
    }
}
