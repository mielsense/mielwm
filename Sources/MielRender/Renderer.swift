// Draws one Scene for one display: the world (backdrop, windows, labels)
// into an offscreen texture, then the lens into the target with the minimap
// composed after it, then the HUD on top. One Renderer can serve every
// display; per-display state is keyed by ScreenInfo.id. Use it from one
// thread (the main thread).

import AppKit
import CoreVideo
import Metal
import MetalPerformanceShaders
import MielCore
import QuartzCore

public enum RenderError: Error {
    case noDevice
    case setup(String)
}

/// Pipelines are compiled once per device and shared by every Renderer.
private final class Pipelines {
    let backdrop: MTLRenderPipelineState
    let window: MTLRenderPipelineState
    let solid: MTLRenderPipelineState
    let texture: MTLRenderPipelineState
    let lens: MTLRenderPipelineState
    let material: MTLRenderPipelineState

    private static let lock = NSLock()
    private static var shared: [UInt64: Pipelines] = [:]

    static func shared(for device: MTLDevice) throws -> Pipelines {
        lock.lock()
        defer { lock.unlock() }
        if let p = shared[device.registryID] { return p }
        let p = try Pipelines(device: device)
        shared[device.registryID] = p
        return p
    }

    private init(device: MTLDevice) throws {
        let library = try device.makeLibrary(source: shaderSource, options: nil)
        func make(_ fragment: String, blend: Bool) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: "quad_vertex")
            d.fragmentFunction = library.makeFunction(name: fragment)
            let c = d.colorAttachments[0]!
            c.pixelFormat = Renderer.pixelFormat
            if blend { // premultiplied source-over
                c.isBlendingEnabled = true
                c.sourceRGBBlendFactor = .one
                c.sourceAlphaBlendFactor = .one
                c.destinationRGBBlendFactor = .oneMinusSourceAlpha
                c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try device.makeRenderPipelineState(descriptor: d)
        }
        backdrop = try make("backdrop_fragment", blend: false)
        window = try make("window_fragment", blend: true)
        solid = try make("solid_fragment", blend: true)
        texture = try make("texture_fragment", blend: true)
        lens = try make("lens_fragment", blend: false)
        material = try make("material_fragment", blend: true)
    }
}

/// Everything kept per display between frames.
private final class ScreenState {
    static let framesInFlight = 3
    let inFlight = DispatchSemaphore(value: framesInFlight)
    /// CoreVideo textures the frame being encoded uses; its command buffer holds them until the
    /// GPU is done. Not longer: they hold capture buffers, and a stream with none free stops.
    var retained: [CVMetalTexture] = []

    var world: MTLTexture?
    let worldPass = MTLRenderPassDescriptor()
    let lensPass = MTLRenderPassDescriptor()

    var wallpaperImage: CGImage?
    var wallpaper: MTLTexture?
    var blurred: MTLTexture?
    var blurredStrength = -1.0

    var labels: [LabelKey: LabelEntry] = [:]
    var labelAlpha: [WindowID: Double] = [:] // fading in for the selection, out for the one before
    var labelTime: Double?
    /// Window names and workspace pills for this frame, in target px: drawn after the lens, so never bent.
    var tags: [(texture: MTLTexture, rect: CGRect, alpha: Double)] = []
    var labelRevision = 0 // the Look revision the cached labels were drawn with
    var workspaceLabels: [String: MTLTexture] = [:]

    var palette: HUDLayer?
    var switcher: HUDLayer?
    var corners: [HUDLayer?] = [nil, nil, nil, nil]
    var toast: HUDLayer?

    var markers = [SIMD4<Float>](repeating: .zero, count: 64)
    var markerDims = [Float](repeating: 0, count: 64)

    /// What the last drawable showed (its time zeroed), to skip frames that would look the same.
    var drawn: (scene: Scene, generations: [UInt64], blink: Double)?
    var caret: (rect: CGRect, alpha: Double)? // where the last frame put the caret, in px

    init() {
        worldPass.colorAttachments[0].loadAction = .clear
        worldPass.colorAttachments[0].storeAction = .store
        worldPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        lensPass.colorAttachments[0].loadAction = .dontCare
        lensPass.colorAttachments[0].storeAction = .store
    }
}

private struct LabelKey: Hashable {
    var title: String
    var bundleID: String?
}

private struct LabelEntry {
    var texture: MTLTexture
    var lastUsed: UInt64
}

public final class Renderer {
    /// The pixel format of every target: set it on the CAMetalLayer.
    public static let pixelFormat: MTLPixelFormat = .bgra8Unorm

    public let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipelines: Pipelines
    private let windowTextures: WindowTextures
    private let hud: HUDPainter
    private var screens: [UInt32: ScreenState] = [:]
    private var frame: UInt64 = 0
    private var theme = Theme(look: Look())
    private var lookRevision = 0 // bumps whenever the Look changes, so caches key on an Int instead of hashing it
    private let placeholderTexture: MTLTexture
    /// False: frames leave the caret out (see `caret(screenID:)`), so an idle search field draws none.
    public var drawsCaret = true

    public init(device: MTLDevice? = nil) throws {
        guard let device = device ?? MTLCreateSystemDefaultDevice() else { throw RenderError.noDevice }
        guard let queue = device.makeCommandQueue() else { throw RenderError.setup("no command queue") }
        self.device = device
        self.queue = queue
        pipelines = try Pipelines.shared(for: device)
        windowTextures = WindowTextures(device: device)
        hud = HUDPainter(device: device)
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        guard let placeholder = device.makeTexture(descriptor: desc) else { throw RenderError.setup("no texture") }
        placeholderTexture = placeholder
    }

    private func state(_ id: UInt32) -> ScreenState {
        if let s = screens[id] { return s }
        let s = ScreenState()
        screens[id] = s
        return s
    }

    /// The desktop picture shown behind the canvas on one display; nil for a
    /// plain dark backdrop.
    public func setWallpaper(_ image: CGImage?, screenID: UInt32) {
        let s = state(screenID)
        guard s.wallpaperImage !== image else { return }
        s.wallpaperImage = image
        s.wallpaper = nil
        s.blurred = nil
        s.drawn = nil
    }

    /// False when a frame of `scene` would look like the last one drawn
    /// into a drawable of its display: same scene, no new window pictures,
    /// no label fading, the caret not changing.
    public func needsDraw(_ scene: Scene, frames: WindowFrameSource) -> Bool {
        guard let s = screens[scene.screen.id], let drawn = s.drawn else { return true }
        var still = scene
        still.time = 0
        return still != drawn.scene || generations(scene, frames) != drawn.generations
            || s.labelAlpha.values.contains { $0 < 0.999 } || (drawsCaret && s.palette?.caret != nil && caretMoved(from: drawn.blink, to: caretBlink(scene.time)))
    }

    /// The caret's fades in steps of about a 60 Hz frame, ending exactly on and off.
    private func caretMoved(from drawn: Double, to now: Double) -> Bool {
        abs(now - drawn) > 0.2 || ((now == 0 || now == 1) && now != drawn)
    }

    /// Where the last frame of that display put the search field's caret, in px from
    /// the top left, its opacity before blinking, and its color (opaque, the display's
    /// own color space, like the frames); nil when it has none.
    public func caret(screenID: UInt32) -> (rect: CGRect, alpha: Double, color: SIMD4<Float>)? {
        screens[screenID]?.caret.map { ($0.rect, $0.alpha, theme.accentRGBA) }
    }

    /// The next `needsDraw` of that display is true (its drawable was resized, hidden or replaced).
    public func invalidate(screenID: UInt32) {
        screens[screenID]?.drawn = nil
    }

    /// Prepares `scene`'s wallpaper (scaled, blurred) without drawing, so
    /// the first frame of the overview does not pay for it.
    public func prepare(_ scene: Scene) {
        guard let cb = queue.makeCommandBuffer() else { return }
        let scale = scene.screen.scale
        prepareWallpaper(state(scene.screen.id), look: scene.look, width: Int(scene.screen.frame.width * scale),
                         height: Int(scene.screen.frame.height * scale), scale: scale, commandBuffer: cb)
        cb.commit()
    }

    /// Lets go of what only an open overlay needs: window pictures (made
    /// again from the frame source), the offscreen world, text and HUD
    /// pieces. The wallpaper stays: it is the slowest to prepare.
    public func purge() {
        windowTextures.removeAll()
        for s in screens.values {
            s.retained = []
            s.world = nil
            s.labels = [:]
            s.tags = []
            s.workspaceLabels = [:]
            s.palette = nil
            s.switcher = nil
            s.corners = [nil, nil, nil, nil]
            s.toast = nil
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
        s.drawn = (still, generations(scene, frames), caretBlink(scene.time))
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
        prepareHUD(scene, s, pxSize: pxSize, scale: scale, minimapTop: minimap?.panel.minY)

        // When the lens pass would be a plain copy, draw the world straight
        // into the target and save a full-screen write and read.
        let lens = LensParameters(look: look, transition: t)
        let direct = lens.isIdentity && minimap == nil && scene.opacity >= 1
        s.worldPass.colorAttachments[0].texture = direct ? target : world
        if let enc = cb.makeRenderCommandEncoder(descriptor: s.worldPass) {
            encodeWorld(scene, frames: frames, enc: enc, state: s, pxSize: pxSize, pad: direct ? .zero : pad, scale: scale, t: t)
            if direct { encodeHUD(scene, enc: enc, state: s, pxSize: pxSize, scale: scale, t: t) }
            enc.endEncoding()
        }
        guard !direct else { return finish() }

        s.lensPass.colorAttachments[0].texture = target
        if let enc = cb.makeRenderCommandEncoder(descriptor: s.lensPass) {
            let map = SIMD4(Float(pad.width) / Float(worldWidth), Float(pad.height) / Float(worldHeight),
                            Float(width) / Float(worldWidth), Float(height) / Float(worldHeight))
            encodeLens(scene, lens, map: map, enc: enc, state: s, world: world, pxSize: pxSize, scale: scale, t: t, minimap: minimap)
            encodeHUD(scene, enc: enc, state: s, pxSize: pxSize, scale: scale, t: t, behind: (world, lens, map))
            enc.endEncoding()
        }
        finish()
    }

    private func finish() {

        windowTextures.prune(frame: frame)
        for s in screens.values { pruneLabels(s) }
    }

    private func quad(_ enc: MTLRenderCommandEncoder, _ rect: CGRect, _ pxSize: CGSize) {
        var q = QuadUniforms(rect: SIMD4(rect), target: SIMD2(Float(pxSize.width), Float(pxSize.height)))
        enc.setVertexBytes(&q, length: MemoryLayout<QuadUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    // MARK: World

    /// The world for a screen of `pxSize`, drawn `pad` px larger on every side
    /// (the lens reads that far past the screen's edges).
    private func encodeWorld(_ scene: Scene, frames: WindowFrameSource, enc: MTLRenderCommandEncoder, state s: ScreenState,
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

        let searching = scene.hud.mode == .search && !scene.hud.query.isEmpty
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

    private func pruneLabels(_ s: ScreenState) {
        guard frame % 120 == 0 else { return }
        s.labels = s.labels.filter { frame - $0.value.lastUsed < 600 }
        // shortcut: a hard cap instead of LRU; only reached with hundreds of distinct live titles.
        if s.labels.count > 512 { s.labels.removeAll() }
    }

    // MARK: Wallpaper

    private func prepareWallpaper(_ s: ScreenState, look: Look, width: Int, height: Int, scale: CGFloat, commandBuffer cb: MTLCommandBuffer) {
        guard look.wallpaperEnabled, let image = s.wallpaperImage else { return }
        if s.wallpaper?.width != width || s.wallpaper?.height != height {
            s.wallpaper = aspectFill(image, width: width, height: height)
            s.blurred = nil
        }
        // The blur is cached and only recomputed when its inputs change. At
        // half size: a blur this wide looks the same, for a quarter of the memory.
        guard look.blur, let sharp = s.wallpaper else { return }
        if s.blurred != nil && s.blurredStrength == look.blurStrength { return }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.pixelFormat, width: max(1, width / 2),
                                                            height: max(1, height / 2), mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private
        guard let half = device.makeTexture(descriptor: desc), let out = device.makeTexture(descriptor: desc) else { return }
        MPSImageBilinearScale(device: device).encode(commandBuffer: cb, sourceTexture: sharp, destinationTexture: half)
        let sigma = Float((10 + 30 * min(max(look.blurStrength, 0), 1)) * scale / 2)
        let blur = MPSImageGaussianBlur(device: device, sigma: sigma)
        blur.edgeMode = .clamp
        blur.encode(commandBuffer: cb, sourceTexture: half, destinationTexture: out)
        s.blurred = out
        s.blurredStrength = look.blurStrength
    }

    private func aspectFill(_ image: CGImage, width: Int, height: Int) -> MTLTexture? {
        guard let bitmap = Bitmap(width: width, height: height) else { return nil }
        let fill = max(CGFloat(width) / CGFloat(image.width), CGFloat(height) / CGFloat(image.height))
        let w = CGFloat(image.width) * fill, h = CGFloat(image.height) * fill
        bitmap.draw(image, in: CGRect(x: (CGFloat(width) - w) / 2, y: (CGFloat(height) - h) / 2, width: w, height: h))
        return bitmap.texture(device: device)
    }

    // MARK: Lens and minimap

    private func minimapPixels(_ scene: Scene, _ s: ScreenState, pxSize: CGSize, scale: CGFloat, t: Double) -> MinimapPixels? {
        guard scene.look.minimapEnabled, t > 0.001, let model = scene.minimap else { return nil }
        return MinimapPixels(model, look: scene.look, screenPx: pxSize, scale: scale, markers: &s.markers, dims: &s.markerDims)
    }

    private func encodeLens(_ scene: Scene, _ lens: LensParameters, map: SIMD4<Float>, enc: MTLRenderCommandEncoder, state s: ScreenState, world: MTLTexture,
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

    // MARK: HUD

    private func prepareHUD(_ scene: Scene, _ s: ScreenState, pxSize: CGSize, scale: CGFloat, minimapTop: CGFloat?) {
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
    private func encodeHUD(_ scene: Scene, enc: MTLRenderCommandEncoder, state s: ScreenState,
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
                                         alpha: Float(alpha * opacity * ease), blur: Float(24 * scale))
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

/// The caret's opacity at `time`: on, a quick fade out, off, a fade back in.
private func caretBlink(_ time: Double) -> Double {
    let phase = time.truncatingRemainder(dividingBy: 1.06) / 1.06
    return min(1, 1 - smoothstep(0.42, 0.5, phase) + smoothstep(0.92, 1.0, phase))
}

private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let k = min(max((x - a) / (b - a), 0), 1)
    return k * k * (3 - 2 * k)
}
