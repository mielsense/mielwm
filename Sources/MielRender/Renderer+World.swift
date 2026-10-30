import CoreGraphics
import Metal
import MielCore

extension Renderer {
    /// The world for a screen of `pxSize`, drawn `pad` px larger on every side
    /// (the lens reads that far past the screen's edges).
    func encodeWorld(_ scene: Scene, frames: WindowFrameSource, enc: MTLRenderCommandEncoder, state s: ScreenState,
                             pxSize: CGSize, pad: CGSize = .zero, scale: CGFloat, t: Double) {
        s.tags.removeAll(keepingCapacity: true)
        let look = scene.look
        let camera = scene.camera
        let deskCenter = scene.desk.center
        let screenOrigin = scene.screen.frame.origin
        let worldSize = CGSize(width: pxSize.width + pad.width * 2, height: pxSize.height + pad.height * 2)
        let full = CGRect(origin: .zero, size: worldSize)
        func px(_ desk: CGRect) -> CGRect {
            CGRect(x: (desk.minX - screenOrigin.x) * scale + pad.width, y: (desk.minY - screenOrigin.y) * scale + pad.height,
                   width: desk.width * scale, height: desk.height * scale)
        }

        // At transition 0 the world is only the windows, exactly where the
        // desktop has them, so the overlay can appear without a visible change.
        if t > 0 {
            var b = BackdropUniforms()
            let zoom = Double(camera.zoom)
            var tileScale = 1.0
            var offset = CGPoint.zero
            if look.parallaxEnabled {
                // Windows move by the camera offset times the zoom; the wallpaper by a fraction of it.
                offset = CGPoint(x: -(camera.center.x - deskCenter.x) * camera.zoom * scale * look.parallaxStrength * t,
                                 y: -(camera.center.y - deskCenter.y) * camera.zoom * scale * look.parallaxStrength * t)
                tileScale = max(0.3, 1 + (pow(min(max(zoom, 0.01), 4), look.parallaxDepth) - 1) * t)
            }
            let tile = CGSize(width: pxSize.width * tileScale, height: pxSize.height * tileScale)
            b.tile = SIMD4(Float((pxSize.width - tile.width) / 2 + offset.x + pad.width),
                           Float((pxSize.height - tile.height) / 2 + offset.y + pad.height),
                           Float(tile.width), Float(tile.height))
            b.solid = SIMD4(0.035, 0.037, 0.045, 1)
            let wallpaper = look.wallpaperEnabled ? s.wallpaper : nil
            b.hasWallpaper = wallpaper == nil ? 0 : 1
            b.blurAlpha = look.blur && s.blurred != nil ? Float(look.blurStrength * t) : 0
            b.dim = Float(look.backgroundDim * t)
            if look.gridEnabled {
                let dots = look.gridDots
                let spacing = look.gridSize * max(camera.zoom, 0.01) * max(scale, 0.01)
                // Level of detail: once marks would crowd, show every other one and
                // fade the level in between, anchored to the world origin.
                let minCell = (dots ? 14 : 12) * max(scale, 1)
                var cell = spacing
                if cell > 0.01 { while cell < minCell { cell *= 2 } }
                let origin = camera.toDesk(CGPoint.zero, deskCenter: deskCenter)
                b.gridOrigin = SIMD2(Float((origin.x - screenOrigin.x) * scale + pad.width), Float((origin.y - screenOrigin.y) * scale + pad.height))
                b.gridOpacity = spacing > 0.01 ? Float(look.gridOpacity * t) : 0
                b.gridCell = Float(cell)
                b.gridFine = Float(smoothstep(minCell, minCell * 1.5, cell))
                b.gridMark = Float(dots ? max(3, (look.gridDotSize * scale).rounded()) : max(1, look.gridWidth * scale))
                b.gridDots = dots ? 1 : 0
            }
            enc.setRenderPipelineState(pipelines.backdrop)
            enc.setFragmentBytes(&b, length: MemoryLayout<BackdropUniforms>.stride, index: 0)
            enc.setFragmentTexture(wallpaper ?? placeholderTexture, index: 0)
            enc.setFragmentTexture(s.blurred ?? placeholderTexture, index: 1)
            quad(enc, full, worldSize)
        }

        let zoom = camera.zoom
        if t > 0 { drawWorkspaces(scene, enc: enc, state: s, pxSize: worldSize, scale: scale, t: t, px: px) }
        if let drop = scene.dropIndicator, t > 0 {
            let r = px(camera.toDesk(drop, deskCenter: deskCenter))
            var u = SolidUniforms()
            u.rect = SIMD4(r)
            u.fill = theme.accentRGBA * Float(0.18 * t)
            u.border = theme.accentRGBA * Float(0.8 * t)
            u.radius = Float(look.windowRounding * scale * zoom)
            u.borderWidth = Float(1.5 * scale)
            enc.setRenderPipelineState(pipelines.solid)
            enc.setFragmentBytes(&u, length: MemoryLayout<SolidUniforms>.stride, index: 0)
            quad(enc, r, worldSize)
        }

        let searching = scene.searching
        let accent = theme.accentRGBA
        let fade = labelFades(scene, s)
        for pass in 0..<2 { // pinned windows last, on top
            for w in scene.windows where w.isPinned == (pass == 1) && w.alpha > 0.001 {
                let desk = w.isPinned ? w.canvasFrame : camera.toDesk(w.canvasFrame, deskCenter: deskCenter)
                let r = px(desk)
                let effectZoom = w.isPinned ? 1 : zoom
                var u = WindowUniforms()
                u.rect = SIMD4(r)
                u.radius = Float(look.windowRounding * scale * effectZoom)
                u.alpha = Float(w.alpha)
                u.dimColor = SIMD4(0.01, 0.015, 0.02, Float(look.dimUnmatched * w.dim * t))
                u.placeholder = SIMD4(0.11, 0.11, 0.12, 1)
                var margin: CGFloat = 0
                if t > 0 && look.windowShadow {
                    let sigma = scale * (6 + 12 * min(effectZoom, 1))
                    u.shadow = 0.5
                    u.shadowSigma = Float(sigma)
                    u.shadowDrop = Float(sigma * 0.35)
                    margin = sigma * 4
                }
                if w.isSelected && t > 0 {
                    // A clean 2 pt ring hugging the window's own corners, no glow.
                    u.accent = SIMD4(accent.x, accent.y, accent.z, Float(t))
                    u.ringWidth = Float(max(2, (2 * scale).rounded()))
                    u.ringGap = u.ringWidth
                    margin = max(margin, CGFloat(u.ringGap) + 2)
                } else if t > 0 && (w.isFocused || (searching && w.dim < 0.01)) {
                    u.outline = Float((w.isFocused ? 0.35 : 0.3) * t)
                    u.outlineWidth = Float(max(1, scale))
                    margin = max(margin, 3 * scale)
                }
                let drawn = r.insetBy(dx: -margin, dy: -margin)
                guard drawn.intersects(full) else { continue }
                if let (texture, cv) = windowTextures.texture(for: w.id, source: frames, frame: frame) {
                    u.hasTexture = 1
                    enc.setFragmentTexture(texture, index: 0)
                    if let cv { s.retained.append(cv) }
                } else {
                    enc.setFragmentTexture(placeholderTexture, index: 0)
                }
                enc.setRenderPipelineState(pipelines.window)
                enc.setFragmentBytes(&u, length: MemoryLayout<WindowUniforms>.stride, index: 0)
                quad(enc, drawn, worldSize)
                if let a = fade[w.id] { addLabel(w, desk: desk, alpha: a, scene: scene, state: s, pxSize: pxSize, scale: scale, t: t) }
            }
        }
    }

    /// Where the lens draws a desk point of this scene's screen, in target px.
    private func lensedPx(_ desk: CGPoint, _ scene: Scene, scale: CGFloat, t: Double) -> CGPoint {
        let o = scene.screen.frame.origin
        let q = lensScreenPoint(CGPoint(x: desk.x - o.x, y: desk.y - o.y), screenSize: scene.screen.frame.size, look: scene.look, transition: t)
        return CGPoint(x: q.x * scale, y: q.y * scale)
    }

    /// How far each window's label has faded in: toward 1 for the selection, 0 for the rest, over 0.15 s.
    private func labelFades(_ scene: Scene, _ s: ScreenState) -> [WindowID: Double] {
        let dt = min(max(scene.time - (s.labelTime ?? scene.time), 0), 0.1)
        let instant = s.labelTime == nil || scene.look.reduceMotion // the first frame (a snapshot) shows the end state
        s.labelTime = scene.time
        var next: [WindowID: Double] = [:]
        for w in scene.windows {
            let target = w.isSelected && scene.look.labels ? 1.0 : 0.0
            let from = instant ? target : s.labelAlpha[w.id] ?? 0
            let a = target > from ? min(target, from + dt / 0.15) : max(target, from - dt / 0.15)
            if a > 0.001 { next[w.id] = a }
        }
        s.labelAlpha = next
        return next
    }

    /// The window's name, centered below it (inside its bottom edge when
    /// that would leave the screen), as Mission Control does.
    private func addLabel(_ w: SceneWindow, desk: CGRect, alpha: Double, scene: Scene, state s: ScreenState,
                          pxSize: CGSize, scale: CGFloat, t: Double) {
        guard t > 0.01 else { return }
        let key = LabelKey(title: w.title.isEmpty ? w.appName : w.title, bundleID: w.bundleID)
        let texture: MTLTexture
        if let entry = s.labels[key] {
            texture = entry.texture
            s.labels[key]?.lastUsed = frame
        } else {
            guard let made = hud.label(title: key.title, bundleID: w.bundleID, scale: scale, theme) else { return }
            texture = made
            s.labels[key] = LabelEntry(texture: made, lastUsed: frame)
        }
        let size = CGSize(width: texture.width, height: texture.height), gap = 10 * scale
        let bottom = lensedPx(CGPoint(x: desk.midX, y: desk.maxY), scene, scale: scale, t: t)
        var y = bottom.y + gap
        if y + size.height > pxSize.height - gap { y = bottom.y - size.height - gap }
        s.tags.append((texture, CGRect(x: (bottom.x - size.width / 2).rounded(), y: y.rounded(), width: size.width, height: size.height),
                       t * alpha * w.alpha))
    }

    /// Each workspace's frame, a quiet rounded rect behind its windows, with
    /// its number and mode in a pill above the top-left corner.
    private func drawWorkspaces(_ scene: Scene, enc: MTLRenderCommandEncoder, state s: ScreenState, pxSize: CGSize, scale: CGFloat,
                                t: Double, px: (CGRect) -> CGRect) {
        guard !scene.workspaces.isEmpty else { return }
        let ink: SIMD4<Float> = theme.look.dark ? SIMD4(1, 1, 1, 1) : SIMD4(0, 0, 0, 1)
        let full = CGRect(origin: .zero, size: pxSize)
        for w in scene.workspaces {
            let r = px(scene.camera.toDesk(w.canvasFrame, deskCenter: scene.desk.center))
            guard r.insetBy(dx: -40 * scale, dy: -40 * scale).intersects(full) else { continue }
            var u = SolidUniforms()
            u.rect = SIMD4(r)
            u.fill = ink * Float((w.isCurrent ? 0.07 : 0.04) * t)
            u.border = ink * Float((w.isCurrent ? 0.22 : 0.12) * (theme.look.increaseContrast ? 2 : 1) * t)
            u.radius = Float(max(theme.look.windowRounding + 6, 12) * scale * scene.camera.zoom)
            u.borderWidth = Float(max(1, scale))
            enc.setRenderPipelineState(pipelines.solid)
            enc.setFragmentBytes(&u, length: MemoryLayout<SolidUniforms>.stride, index: 0)
            quad(enc, r, pxSize)

            let key = "\(w.number ?? 0)/\(w.mode.rawValue)/\(w.isCurrent)/\(scale)"
            if s.workspaceLabels[key] == nil {
                if s.workspaceLabels.count > 64 { s.workspaceLabels.removeAll() }
                s.workspaceLabels[key] = hud.workspaceLabel(number: w.number, mode: w.mode, current: w.isCurrent, scale: scale, theme)
            }
            let desk = scene.camera.toDesk(w.canvasFrame, deskCenter: scene.desk.center)
            if !w.emptyMessage.isEmpty {
                let messageKey = "message/\(w.emptyMessage)/\(scale)"
                if s.workspaceLabels[messageKey] == nil { s.workspaceLabels[messageKey] = hud.notice(w.emptyMessage, scale: scale, theme) }
                if let message = s.workspaceLabels[messageKey], r.width > CGFloat(message.width) + 32 * scale {
                    let c = lensedPx(desk.center, scene, scale: scale, t: t)
                    s.tags.append((message, CGRect(x: (c.x - CGFloat(message.width) / 2).rounded(), y: (c.y - CGFloat(message.height) / 2).rounded(),
                                                   width: CGFloat(message.width), height: CGFloat(message.height)), t))
                }
            }
            guard let texture = s.workspaceLabels[key], r.width > CGFloat(texture.width) else { continue }
            let corner = lensedPx(desk.origin, scene, scale: scale, t: t)
            s.tags.append((texture, CGRect(x: corner.x.rounded(), y: (corner.y - CGFloat(texture.height) - 8 * scale).rounded(),
                                           width: CGFloat(texture.width), height: CGFloat(texture.height)), t * (w.isCurrent ? 1 : 0.8)))
        }
    }

    func pruneLabels(_ s: ScreenState) {
        guard frame % 120 == 0 else { return }
        s.labels = s.labels.filter { frame - $0.value.lastUsed < 600 }
        // shortcut: a hard cap instead of LRU; only reached with hundreds of distinct live titles.
        if s.labels.count > 512 { s.labels.removeAll() }
    }
}
