import CoreGraphics
import Foundation

// What pointer gestures do to the canvas: pans, zooms, pinches, drags and the minimap.

extension CanvasState {
    mutating func handle(_ g: PointerGesture) {
        switch g {
        case let .pan(delta):
            if !isOverview { isPanning = true }
            let c = animator.camera, k = settings.panSensitivity / c.zoom
            let moved = Camera(center: CGPoint(x: c.center.x - delta.dx * k, y: c.center.y - delta.dy * k), zoom: c.zoom)
            animator.warp(to: moved, now: now)
        case let .panEnded(velocity):
            let c = animator.camera, k = settings.panSensitivity / c.zoom
            let v = CGVector(dx: -velocity.dx * k, dy: -velocity.dy * k)
            let glide = 0.15 // seconds of momentum
            let target = Camera(center: CGPoint(x: c.center.x + v.dx * glide, y: c.center.y + v.dy * glide), zoom: c.zoom)
            if isOverview { fly(to: target, velocity: v) } else { settle(at: target, velocity: v) }
            isPanning = false
        case let .zoom(point, factor):
            if !isOverview { // zooming out at 100% opens the overview there
                return factor < 1 ? openOverview(zoom: animator.target.zoom * factor, at: point) : ()
            }
            fly(to: zoomed(animator.target, at: point, to: animator.target.zoom * factor))
        case let .pinch(point, factor):
            guard isOverview else { return handle(.zoom(at: point, factor: factor)) }
            animator.warp(to: zoomed(animator.camera, at: point, to: animator.camera.zoom * factor), now: now)
        case let .dragWindow(id, delta):
            guard let i = index(id) else { return }
            if dragging != id {
                checkpoint("drag", window: id)
                dragging = id
            }
            let z = isOverview ? animator.camera.zoom : 1
            if windows[i].pinned != nil {
                windows[i].pinned = windows[i].pinned!.offsetBy(delta)
            } else {
                windows[i].frame = windows[i].frame.offsetBy(dx: delta.dx / z, dy: delta.dy / z)
            }
            let spot = windows[i].workspace != nil ? dropSpot(i) : nil
            dropIndicator = isOverview ? spot?.tile ?? (settings.snapEnabled ? snapToGrid(windows[i].frame, grid: look.gridSize) : nil) : nil
            if !isOverview { sync([id]) }
        case let .resizeWindow(id, corner, delta):
            guard let i = index(id), windows[i].isResizable, windows[i].pinned == nil else { return }
            if dragging != id {
                checkpoint("resize", window: id)
                dragging = id
            }
            let z = isOverview ? animator.camera.zoom : 1
            let dx = delta.dx / z, dy = delta.dy / z
            var f = windows[i].frame
            let left = corner == .topLeft || corner == .bottomLeft, top = corner == .topLeft || corner == .topRight
            let w = max(120, f.width + (left ? -dx : dx)), h = max(80, f.height + (top ? -dy : dy))
            if left { f.origin.x = f.maxX - w }
            if top { f.origin.y = f.maxY - h }
            f.size = CGSize(width: w, height: h)
            windows[i].frame = f
            fills[id] = nil
            if !isOverview { sync([id]) }
        case let .dragEnded(id):
            guard let i = index(id) else { return }
            if let ws = workspace(of: id), let tile = tiles(ws).first(where: { $0.id == id })?.frame {
                dragging = nil
                dropIndicator = nil
                if !windows[i].frame.size.isClose(to: tile.size) { return userChangedTile(i, to: windows[i].frame, resizing: true) } // resized
                // Dropped on a workspace: it moves there (or within it); on open canvas it floats there.
                if let spot = dropSpot(i) { return join(id, spot.slot, at: spot.position) }
                leave(id)
            }
            if isOverview, settings.snapEnabled, windows[i].pinned == nil {
                windows[i].frame = snapToGrid(windows[i].frame, grid: look.gridSize)
            }
            dragging = nil
            dropIndicator = nil
            if !isOverview { sync([id]) }
            layoutRevision += 1
        case let .minimapJump(p):
            fly(to: camera(showing: p, atScreenPoint: overviewFreeArea(on: activeScreen).center, on: activeScreen, zoom: animator.target.zoom))
        }
    }
}
