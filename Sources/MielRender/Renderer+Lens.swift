import Metal
import MielCore

extension Renderer {
    func minimapPixels(_ scene: Scene, _ s: ScreenState, pxSize: CGSize, scale: CGFloat, t: Double) -> MinimapPixels? {
        guard scene.look.minimapEnabled, t > 0.001, let model = scene.minimap else { return nil }
        return MinimapPixels(model, look: scene.look, screenPx: pxSize, scale: scale, markers: &s.markers, dims: &s.markerDims)
    }

    func encodeLens(_ scene: Scene, _ lens: LensParameters, map: SIMD4<Float>, enc: MTLRenderCommandEncoder, state s: ScreenState, world: MTLTexture,
                            pxSize: CGSize, scale: CGFloat, t: Double, minimap: MinimapPixels?) {
        var u = LensUniforms()
        u.size = SIMD2(Float(pxSize.width), Float(pxSize.height))
        u.map = map
        u.distort = Float(lens.distort)
        u.contrast = Float(lens.contrast)
        u.feather = Float(lens.feather)
        u.edgeBlur = Float(lens.edgeBlur)
        u.edgeBlurStart = Float(lens.edgeBlurStart)
        u.vignette = Float(lens.vignette)
        u.chromatic = Float(lens.chromatic)
        u.pixelScale = Float(scale)
        u.opacity = Float(min(max(scene.opacity, 0), 1))
        if let minimap {
            u.panel = SIMD4(minimap.panel)
            u.button = SIMD4(minimap.button)
            u.viewport = SIMD4(minimap.viewport)
            u.active = theme.accentRGBA
            u.inactive = theme.markerRGBA
            u.panelColor = theme.panelRGBA
            u.hairline = theme.edgeRGBA
            u.line = theme.lineRGBA
            u.minimapOpacity = Float(scene.look.reduceTransparency ? 1 : scene.look.minimapOpacity)
            u.minimapTransition = Float(t)
            u.count = Int32(minimap.count)
            u.workspaceCount = Int32(minimap.workspaceCount)
            u.liquid = scene.look.liquid ? 1 : 0
            let focused = scene.minimap?.focusedIndex ?? -1
            u.focused = Int32(focused < minimap.count ? focused : -1)
        }
        enc.setRenderPipelineState(pipelines.lens)
        enc.setFragmentBytes(&u, length: MemoryLayout<LensUniforms>.stride, index: 0)
        // Both arrays always hold 64 entries; Metal needs a non-zero length.
        let count = max(1, Int(u.count + u.workspaceCount))
        s.markers.withUnsafeBytes { enc.setFragmentBytes($0.baseAddress!, length: count * MemoryLayout<SIMD4<Float>>.stride, index: 1) }
        s.markerDims.withUnsafeBytes { enc.setFragmentBytes($0.baseAddress!, length: max(16, count * 4), index: 2) }
        enc.setFragmentTexture(world, index: 0)
        quad(enc, CGRect(origin: .zero, size: pxSize), pxSize)
    }
}
