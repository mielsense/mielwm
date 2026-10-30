import Metal
import MielCore

extension Renderer {
    func prepareHUD(_ scene: Scene, _ s: ScreenState, pxSize: CGSize, scale: CGFloat, minimapTop: CGFloat?) {
        let model = scene.hud
        let screen = scene.screen
        let view = HUDView(size: pxSize, scale: scale,
                           topInset: max(screen.safeAreaTop, screen.visibleFrame.minY - screen.frame.minY) * scale,
                           bottomInset: max(0, screen.frame.maxY - screen.visibleFrame.maxY) * scale,
                           minimapTop: minimapTop)
        var base = Hasher()
        base.combine(lookRevision)
        base.combine(pxSize.width)
        base.combine(pxSize.height)
        base.combine(scale)
        base.combine(view.topInset)
        base.combine(view.bottomInset)
        let baseKey = base.finalize()

        // Each piece is keyed only by what it shows, so a ticking corner
        // readout never re-rasterizes the palette.
        func key(_ build: (inout Hasher) -> Void) -> Int {
            var h = Hasher()
            h.combine(baseKey)
            build(&h)
            return h.finalize()
        }

        switch model.mode {
        case .search, .help:
            let k = key {
                $0.combine(model.mode); $0.combine(model.query); $0.combine(model.markedText); $0.combine(model.placeholder)
                $0.combine(model.rows); $0.combine(model.selectedRow); $0.combine(model.footer); $0.combine(model.help)
            }
            if s.palette?.key != k { s.palette = hud.palette(model, theme, view, key: k) }
            s.switcher = nil
        case .switcher:
            let k = key { $0.combine(model.rows); $0.combine(model.selectedRow); $0.combine(model.footer) }
            if s.switcher?.key != k { s.switcher = hud.switcher(model, theme, view, key: k) }
            s.palette = nil
        case .hidden:
            s.palette = nil
            s.switcher = nil
        }

        for i in 0..<4 {
            let text = i < model.corners.count ? model.corners[i] : "" // Core leaves out what is off
            if text.isEmpty {
                s.corners[i] = nil
                continue
            }
            let k = key { $0.combine(i); $0.combine(text); $0.combine(minimapTop) }
            if s.corners[i]?.key != k { s.corners[i] = hud.corner(text, index: i, theme, view, key: k) }
        }

        if let toast = model.toast, !toast.isEmpty {
            let k = key { $0.combine(toast) }
            if s.toast?.key != k { s.toast = hud.toast(toast, theme, view, key: k) }
        } else {
            s.toast = nil
        }
    }

    /// `behind`: the world and its lens, to blur behind panels; nil when the
    /// world was drawn straight into the target (there is nothing to blur).
    func encodeHUD(_ scene: Scene, enc: MTLRenderCommandEncoder, state s: ScreenState,
                           pxSize: CGSize, scale: CGFloat, t: Double, behind: (MTLTexture, LensParameters, SIMD4<Float>)? = nil) {
        let opacity = min(max(scene.opacity, 0), 1)
        let ease = smoothstep(0, 1, t)
        func draw(_ layer: HUDLayer?, alpha: Double, dy: CGFloat = 0) {
            guard let layer, alpha > 0.001 else { return }
            if let (world, lens, map) = behind, let panel = layer.panel, t > 0.001, !scene.look.reduceTransparency {
                // The material: what is behind the panel, blurred, under its translucent tint.
                let r = panel.offsetBy(dx: layer.rect.minX, dy: layer.rect.minY + dy)
                var m = MaterialUniforms(rect: SIMD4(r), map: map, size: SIMD2(Float(pxSize.width), Float(pxSize.height)),
                                         radius: Float(layer.radius), distort: Float(lens.distort), contrast: Float(lens.contrast),
                                         alpha: Float(alpha * opacity * ease), blur: Float((scene.look.liquid ? 5 : 24) * scale),
                                         liquid: scene.look.liquid ? 1 : 0, scale: Float(scale), dark: scene.look.dark ? 1 : 0)
                enc.setRenderPipelineState(pipelines.material)
                enc.setFragmentBytes(&m, length: MemoryLayout<MaterialUniforms>.stride, index: 0)
                enc.setFragmentTexture(world, index: 0)
                quad(enc, r, pxSize)
            }
            var u = TexturedUniforms(alpha: Float(alpha * opacity))
            enc.setRenderPipelineState(pipelines.texture)
            enc.setFragmentBytes(&u, length: MemoryLayout<TexturedUniforms>.stride, index: 0)
            enc.setFragmentTexture(layer.texture, index: 0)
            quad(enc, layer.rect.offsetBy(dx: 0, dy: dy), pxSize)
        }

        for tag in s.tags {
            var u = TexturedUniforms(alpha: Float(tag.alpha * opacity))
            enc.setRenderPipelineState(pipelines.texture)
            enc.setFragmentBytes(&u, length: MemoryLayout<TexturedUniforms>.stride, index: 0)
            enc.setFragmentTexture(tag.texture, index: 0)
            quad(enc, tag.rect, pxSize)
        }
        for corner in s.corners { draw(corner, alpha: ease) }

        // The palette eases in with the zoom and settles downward into place.
        let slide = -(1 - ease) * 18 * scale
        draw(s.palette, alpha: ease, dy: slide)
        s.caret = nil
        if let palette = s.palette, let caret = palette.caret, ease > 0.001 {
            let r = caret.offsetBy(dx: palette.rect.minX, dy: palette.rect.minY + slide)
            s.caret = (r, ease * opacity)
        }
        if drawsCaret, let (r, alpha) = s.caret {
            let blink = caretBlink(scene.time)
            var u = SolidUniforms()
            u.rect = SIMD4(r)
            u.fill = theme.accentRGBA * Float(blink * alpha)
            enc.setRenderPipelineState(pipelines.solid)
            enc.setFragmentBytes(&u, length: MemoryLayout<SolidUniforms>.stride, index: 0)
            quad(enc, r, pxSize)
        }
        draw(s.switcher, alpha: 1)
        draw(s.toast, alpha: 1)
    }
}
