// Draws one Scene for one display: the world (backdrop, windows) into an
// offscreen texture, then the lens into the target with the minimap composed
// after it, then the tags (window names, workspace pills) on top. The
// overview's chrome is native views over it (Sources/mielwm/ChromeViews.swift),
// so the Scene's HUD is never drawn here. One Renderer can serve every
// display; per-display state is keyed by ScreenInfo.id. Use it from one
// thread (the main thread).

import AppKit
import CoreVideo
import Metal
import MielCore
import QuartzCore

public enum RenderError: Error {
    case noDevice
    case setup(String)
}
public final class Renderer {
    /// The pixel format of every target: set it on the CAMetalLayer.
    public static let pixelFormat: MTLPixelFormat = .bgra8Unorm

    public let device: MTLDevice
    let queue: MTLCommandQueue
    let pipelines: Pipelines
    let windowTextures: WindowTextures
    let painter: TagPainter
    var screens: [UInt32: ScreenState] = [:]
    var frame: UInt64 = 0
    var theme = Theme(look: Look())
    var lookRevision = 0 // bumps whenever the Look changes, so caches key on an Int instead of hashing it
    let placeholderTexture: MTLTexture

    public init(device: MTLDevice? = nil) throws {
        guard let device = device ?? MTLCreateSystemDefaultDevice() else { throw RenderError.noDevice }
        guard let queue = device.makeCommandQueue() else { throw RenderError.setup("no command queue") }
        self.device = device
        self.queue = queue
        pipelines = try Pipelines.shared(for: device)
        windowTextures = WindowTextures(device: device)
        painter = TagPainter(device: device)
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        guard let placeholder = device.makeTexture(descriptor: desc) else { throw RenderError.setup("no texture") }
        placeholderTexture = placeholder
    }

    func state(_ id: UInt32) -> ScreenState {
        if let s = screens[id] { return s }
        let s = ScreenState()
        screens[id] = s
        return s
    }

    /// The desktop picture shown behind the canvas on one display; nil for a
    /// plain dark backdrop.
    public func setWallpaper(_ image: CGImage?, screenID: UInt32) {
        let s = state(screenID)
        s.wallpaperImage = image
        s.wallpaper = nil
        s.blurred = nil
        s.drawn = nil
    }

    /// False when a frame of `scene` would look like the last one drawn
    /// into a drawable of its display: same scene, no new window pictures,
    /// no label fading.
    public func needsDraw(_ scene: Scene, frames: WindowFrameSource) -> Bool {
        guard let s = screens[scene.screen.id], let drawn = s.drawn else { return true }
        var still = scene
        still.time = 0
        return still != drawn.scene || generations(scene, frames) != drawn.generations || s.labelAlpha.values.contains { $0 < 0.999 }
    }

    /// The next `needsDraw` of that display is true (its drawable was resized, hidden or replaced).
    public func invalidate(screenID: UInt32) {
        screens[screenID]?.drawn = nil
    }

    /// Prepares `scene`'s wallpaper (scaled, blurred) without drawing, so
    /// the first frame of the overview does not pay for it. The texture then
    /// holds the picture and the image goes, which would double its memory:
    /// call `setWallpaper` again when the display's size changes.
    public func prepare(_ scene: Scene) {
        guard let cb = queue.makeCommandBuffer() else { return }
        let s = state(scene.screen.id), scale = scene.screen.scale
        prepareWallpaper(s, look: scene.look, width: Int(scene.screen.frame.width * scale),
                         height: Int(scene.screen.frame.height * scale), scale: scale, commandBuffer: cb)
        cb.commit()
        if s.wallpaper != nil { s.wallpaperImage = nil }
    }

    /// Lets go of what only an open overlay needs: window pictures (made
    /// again from the frame source), the offscreen world and the tags.
    /// The wallpaper stays: it is the slowest to prepare.
    public func purge() {
        windowTextures.removeAll()
        for s in screens.values {
            s.retained = []
            s.world = nil
            s.labels = [:]
            s.tags = []
            s.workspaceLabels = [:]
            s.drawn = nil
        }
    }

    private func generations(_ scene: Scene, _ frames: WindowFrameSource) -> [UInt64] {
        scene.windows.map { frames.generation(for: $0.id) }
    }

    // MARK: - Public drawing

    /// Draws `scene` into a drawable of the scene's display and presents it.
    /// Blocks only when three frames for this display are already queued.
    public func draw(_ scene: Scene, frames: WindowFrameSource, into drawable: CAMetalDrawable) {
        let s = state(scene.screen.id)
        s.inFlight.wait()
        guard let cb = queue.makeCommandBuffer() else {
            s.inFlight.signal()
            return
        }
        encode(scene, frames: frames, target: drawable.texture, commandBuffer: cb, state: s)
        var still = scene
        still.time = 0
        s.drawn = (still, generations(scene, frames))
        let semaphore = s.inFlight, held = s.retained
        s.retained = []
        cb.addCompletedHandler { _ in
            withExtendedLifetime(held) {}
            semaphore.signal()
        }
        cb.present(drawable)
        cb.commit()
    }

    /// Renders offscreen and waits for the result. `pixelSize` defaults to
    /// the display's frame times its backing scale.
    public func renderImage(_ scene: Scene, frames: WindowFrameSource, pixelSize: CGSize? = nil) -> CGImage? {
        let size = pixelSize ?? CGSize(width: scene.screen.frame.width * scene.screen.scale,
                                       height: scene.screen.frame.height * scene.screen.scale)
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.pixelFormat, width: Int(size.width),
                                                            height: Int(size.height), mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let target = device.makeTexture(descriptor: desc), let cb = queue.makeCommandBuffer() else { return nil }
        let s = state(scene.screen.id)
        s.inFlight.wait()
        encode(scene, frames: frames, target: target, commandBuffer: cb, state: s)
        s.drawn = nil // it moved label fades on
        cb.commit()
        cb.waitUntilCompleted()
        s.retained = []
        s.inFlight.signal()

        guard let bitmap = Bitmap(width: target.width, height: target.height), let data = bitmap.ctx.data else { return nil }
        target.getBytes(data, bytesPerRow: bitmap.ctx.bytesPerRow, from: MTLRegionMake2D(0, 0, target.width, target.height), mipmapLevel: 0)
        return bitmap.ctx.makeImage()
    }

    /// Renders offscreen and writes a PNG.
    public func renderPNG(_ scene: Scene, frames: WindowFrameSource, to url: URL, pixelSize: CGSize? = nil) throws {
        guard let image = renderImage(scene, frames: frames, pixelSize: pixelSize) else { throw RenderError.setup("render failed") }
        try Renderer.writePNG(image, to: url)
    }

    public static func writePNG(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw RenderError.setup("cannot write \(url.path)")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw RenderError.setup("cannot write \(url.path)") }
    }

    // MARK: - Frame

    private func encode(_ scene: Scene, frames: WindowFrameSource, target: MTLTexture, commandBuffer cb: MTLCommandBuffer, state s: ScreenState) {
        frame &+= 1
        s.retained = []

        let width = target.width, height = target.height
        let pxSize = CGSize(width: width, height: height)
        let scale = CGFloat(width) / max(scene.screen.frame.width, 1)
        let t = min(max(scene.transition, 0), 1)
        let look = scene.look
        if theme.look != look {
            theme = Theme(look: look)
            lookRevision += 1
        }
        if s.labelRevision != lookRevision {
            s.labels.removeAll()
            s.workspaceLabels.removeAll()
            s.labelRevision = lookRevision
        }

        let over = LensParameters.overscan(look)
        let pad = CGSize(width: (over * Double(width)).rounded(.up), height: (over * Double(height)).rounded(.up))
        let worldWidth = width + Int(pad.width) * 2, worldHeight = height + Int(pad.height) * 2
        if s.world?.width != worldWidth || s.world?.height != worldHeight {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.pixelFormat, width: worldWidth, height: worldHeight,
                                                                mipmapped: false)
            desc.usage = [.renderTarget, .shaderRead]
            desc.storageMode = .private
            s.world = device.makeTexture(descriptor: desc)
        }
        guard let world = s.world else { return }

        // Text and wallpaper work happens on the CPU before encoding. The
        // wallpaper is prepared at rest too, so the first zoomed frame has it.
        prepareWallpaper(s, look: look, width: width, height: height, scale: scale, commandBuffer: cb)
        let minimap = minimapPixels(scene, s, pxSize: pxSize, scale: scale, t: t)

        // When the lens pass would be a plain copy, draw the world straight
        // into the target and save a full-screen write and read.
        let lens = LensParameters(look: look, transition: t)
        let direct = lens.isIdentity && minimap == nil && scene.opacity >= 1
        s.worldPass.colorAttachments[0].texture = direct ? target : world
        if let enc = cb.makeRenderCommandEncoder(descriptor: s.worldPass) {
            encodeWorld(scene, frames: frames, enc: enc, state: s, pxSize: pxSize, pad: direct ? .zero : pad, scale: scale, t: t)
            if direct { encodeTags(scene, enc: enc, state: s, pxSize: pxSize) }
            enc.endEncoding()
        }
        guard !direct else { return finish() }

        s.lensPass.colorAttachments[0].texture = target
        if let enc = cb.makeRenderCommandEncoder(descriptor: s.lensPass) {
            let map = SIMD4(Float(pad.width) / Float(worldWidth), Float(pad.height) / Float(worldHeight),
                            Float(width) / Float(worldWidth), Float(height) / Float(worldHeight))
            encodeLens(scene, lens, map: map, enc: enc, state: s, world: world, pxSize: pxSize, scale: scale, t: t, minimap: minimap)
            encodeTags(scene, enc: enc, state: s, pxSize: pxSize)
            enc.endEncoding()
        }
        finish()
    }

    private func finish() {
        windowTextures.prune(frame: frame)
        for s in screens.values { pruneLabels(s) }
    }

    func quad(_ enc: MTLRenderCommandEncoder, _ rect: CGRect, _ pxSize: CGSize) {
        var q = QuadUniforms(rect: SIMD4(rect), target: SIMD2(Float(pxSize.width), Float(pxSize.height)))
        enc.setVertexBytes(&q, length: MemoryLayout<QuadUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}

func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let k = min(max((x - a) / (b - a), 0), 1)
    return k * k * (3 - 2 * k)
}
