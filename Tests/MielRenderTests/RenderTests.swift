import CoreGraphics
import Foundation
import Metal
import QuartzCore
import MielCore
@testable import MielRender
import Testing

private let outDir = URL(fileURLWithPath: "/tmp/mielwm-render")

/// BGRA bytes of an image, premultiplied, row 0 at the top.
private struct Pixels {
    let bytes: [UInt8]
    let width: Int
    let height: Int

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            ctx.setBlendMode(.copy)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        self.bytes = bytes
    }

    subscript(x: Int, y: Int) -> [Int] {
        let i = (y * width + x) * 4
        return bytes[i..<(i + 4)].map(Int.init)
    }

    func close(_ a: [Int], _ b: [Int], _ tolerance: Int = 1) -> Bool {
        zip(a, b).allSatisfy { abs($0 - $1) <= tolerance }
    }

    /// Enough visible, varied pixels to be a real picture.
    var looksDrawn: Bool {
        var visible = 0
        var colors = Set<UInt32>()
        for i in stride(from: 0, to: bytes.count, by: 4 * 7) where bytes[i + 3] > 0 {
            visible += 1
            if colors.count < 500 { colors.insert(UInt32(bytes[i]) | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]) << 16) }
        }
        return visible > bytes.count / 4 / 7 / 10 && colors.count >= 100
    }
}

private func name(_ state: String, _ screen: ScreenInfo) -> String {
    "\(state)-\(screen.scale > 1 ? "retina" : "1080p")"
}

/// Renders `scene` with synthetic window content and writes it for review.
@discardableResult
private func render(_ scene: Scene, _ state: String, frames: SyntheticFrames? = nil, wallpaper: Bool = true) throws -> Pixels {
    let renderer = try Renderer()
    if wallpaper { renderer.setWallpaper(Fixture.wallpaper, screenID: scene.screen.id) }
    let frames = frames ?? SyntheticFrames(windows: scene.windows, scale: 2)
    let image = try #require(renderer.renderImage(scene, frames: frames))
    #expect(image.width == Int(scene.screen.frame.width * scene.screen.scale))
    try Renderer.writePNG(image, to: outDir.appendingPathComponent("\(name(state, scene.screen)).png"))
    return Pixels(image)
}

@Suite(.serialized) struct RenderTests {
    @Test func uniformLayoutsMatchTheShaders() {
        #expect(MemoryLayout<QuadUniforms>.stride == 32)
        #expect(MemoryLayout<BackdropUniforms>.stride == 80)
        #expect(MemoryLayout<WindowUniforms>.stride == 112)
        #expect(MemoryLayout<SolidUniforms>.stride == 64)
        #expect(MemoryLayout<TexturedUniforms>.stride == 16)
        #expect(MemoryLayout<LensUniforms>.stride == 208)
        #expect(MemoryLayout<MaterialUniforms>.stride == 64)
    }

    @Test func hintsSplitIntoKeysAndLabels() {
        let segments = hintSegments("{⌃0} Fit all  {⎋} Back")
        #expect(segments.map(\.text) == ["⌃0", " Fit all  ", "⎋", " Back"])
        #expect(segments.map(\.isKey) == [true, false, true, false])
    }

    @Test func lensIsIdentityAtRestAndKeepsTheCenter() {
        var look = Look()
        let size = CGSize(width: 3024, height: 1964)
        func near(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9 }
        #expect(LensParameters(look: look, transition: 0).isIdentity)
        #expect(near(lensSourcePoint(CGPoint(x: 10, y: 20), screenSize: size, look: look, transition: 0), CGPoint(x: 10, y: 20)))
        let full = LensParameters(look: look, transition: 1)
        #expect(full.distort == look.lensStrength && full.contrast == look.lensEdgeScale)
        #expect(near(lensSourcePoint(CGPoint(x: 1512, y: 982), screenSize: size, look: look, transition: 1), CGPoint(x: 1512, y: 982)))
        // At the defaults the barrel outweighs the edge scale: the edge reads past the screen, which the world's overscan covers.
        let edge = lensSourcePoint(CGPoint(x: 0, y: 0), screenSize: size, look: look, transition: 1)
        #expect(edge.x < 0 && -edge.x < size.width * LensParameters.overscan(look))
        #expect(-edge.y < size.height * LensParameters.overscan(look))
        look.lensTransitionPower = 2
        #expect(LensParameters(look: look, transition: 0.5).progress == 0.25)
        look.lensEnabled = false
        #expect(LensParameters(look: look, transition: 1) == LensParameters(look: look, transition: 0))
    }

    @Test(arguments: Fixture.screens) func desktopAtRestIsExactlyTheDesktop(screen: ScreenInfo) throws {
        // Dim and selection must not show at rest.
        let windows = Fixture.deskWindows.map { w in
            var w = w
            w.dim = 1
            w.isSelected = w.id.number == 2
            return w
        }
        let scene = Scene(screen: screen, desk: Fixture.desk, camera: Camera(center: Fixture.desk.center), transition: 0,
                          windows: windows, look: Look(), minimap: Fixture.minimap(windows, camera: Camera(center: Fixture.desk.center), focused: 0))
        let frames = SyntheticFrames(windows: windows, scale: screen.scale)
        let pixels = try render(scene, "desktop", frames: frames)
        #expect(pixels.looksDrawn)
        // No backdrop, dim, grid or chrome: where no window is, nothing is drawn.
        #expect(pixels[0, 0] == [0, 0, 0, 0])
        #expect(pixels[pixels.width - 1, pixels.height - 1] == [0, 0, 0, 0])
        // Window pixels are the window image, untouched.
        let w = try #require(windows.first { $0.canvasFrame.intersects(screen.frame) && !$0.canvasFrame.contains(screen.frame.origin) })
        let source = Pixels(try #require(SyntheticFrames.paint(w, width: Int(w.canvasFrame.width * screen.scale),
                                                                height: Int(w.canvasFrame.height * screen.scale), scale: screen.scale)))
        let visible = w.canvasFrame.intersection(screen.frame)
        let probe = CGPoint(x: visible.midX, y: visible.midY)
        let sx = Int((probe.x - w.canvasFrame.minX) * screen.scale), sy = Int((probe.y - w.canvasFrame.minY) * screen.scale)
        let px = Int((probe.x - screen.frame.minX) * screen.scale), py = Int((probe.y - screen.frame.minY) * screen.scale)
        #expect(pixels.close(pixels[px, py], source[sx, sy]))
    }

    @Test(arguments: Fixture.screens) func overview(screen: ScreenInfo) throws {
        var hud = HUDModel()
        hud.corners = Fixture.corners
        hud.toast = "Tidied 12 windows  {⌃Z} Undo"
        var scene = Fixture.overview(screen, hud: hud)
        scene.workspaces = Fixture.workspaces
        scene.minimap?.workspaces = Fixture.workspaces.map(\.canvasFrame)
        scene.dropIndicator = CGRect(x: -1150, y: 910, width: 900, height: 380) // open space on the Retina panel
        let pixels = try render(scene, "overview")
        #expect(pixels.looksDrawn)
        // Opaque backdrop everywhere once zoomed out.
        #expect(pixels[2, 2][3] == 255)
    }

    @Test(arguments: Fixture.screens) func search(screen: ScreenInfo) throws {
        let (hud, windows) = Fixture.searchHUD()
        let pixels = try render(Fixture.overview(screen, hud: hud, windows: windows, selected: windows[0].id), "search")
        #expect(pixels.looksDrawn)
    }

    /// Light chrome: the palette's panel is light where dark chrome's is dark.
    @Test func lightAppearance() throws {
        let (hud, windows) = Fixture.searchHUD()
        var look = Look()
        func panelPixel(dark: Bool) throws -> [Int] {
            look.dark = dark
            var scene = Fixture.overview(Fixture.retina, look: look, hud: hud, windows: windows, selected: windows[0].id)
            scene.workspaces = Fixture.workspaces
            let pixels = try render(scene, dark ? "search-dark" : "search-light")
            // Inside the search field, right of the query, where only the panel is.
            return pixels[pixels.width / 2 + 500, Int(Fixture.retina.frame.height * look.paletteTop * 2) + 40]
        }
        let dark = try panelPixel(dark: true), light = try panelPixel(dark: false)
        #expect(dark[0] < 110 && light[0] > 170, "dark \(dark), light \(light)")
    }

    @Test(arguments: Fixture.screens) func help(screen: ScreenInfo) throws {
        let pixels = try render(Fixture.overview(screen, hud: Fixture.helpHUD()), "help")
        #expect(pixels.looksDrawn)
    }

    /// The ⌥Tab strip shows over the plain desktop.
    @Test(arguments: Fixture.screens) func switcher(screen: ScreenInfo) throws {
        let scene = Scene(screen: screen, desk: Fixture.desk, camera: Camera(center: Fixture.desk.center), transition: 0,
                          windows: Fixture.deskWindows, look: Look(), hud: Fixture.switcherHUD())
        let pixels = try render(scene, "switcher")
        #expect(pixels.looksDrawn)
        #expect(pixels[0, 0] == [0, 0, 0, 0])
    }

    @Test(arguments: Fixture.screens) func lensWithEveryEffect(screen: ScreenInfo) throws {
        var look = Look()
        look.lensStrength = 0.3
        look.lensFeather = 0.04
        look.edgeBlur = 0.7
        look.vignette = 0.6
        look.chromatic = 0.8
        look.blur = true
        look.gridDots = false
        var hud = HUDModel()
        hud.corners = Fixture.corners
        let pixels = try render(Fixture.overview(screen, look: look, hud: hud), "lens")
        #expect(pixels.looksDrawn)
    }

    @Test func lensStrengthBendsTheEdgesButNotTheCenter() throws {
        let screen = Fixture.retina
        var look = Look()
        look.lensEdgeScale = 1
        look.lensFeather = 0
        look.minimapEnabled = false
        func image(strength: Double) throws -> Pixels {
            look.lensStrength = strength
            let scene = Fixture.overview(screen, look: look)
            let renderer = try Renderer()
            renderer.setWallpaper(Fixture.wallpaper, screenID: screen.id)
            return Pixels(try #require(renderer.renderImage(scene, frames: SyntheticFrames(windows: scene.windows, scale: 2))))
        }
        let flat = try image(strength: 0), bent = try image(strength: 0.3)
        let cx = flat.width / 2, cy = flat.height / 2
        for y in (cy - 2)...(cy + 2) {
            for x in (cx - 2)...(cx + 2) { #expect(flat.close(flat[x, y], bent[x, y])) }
        }
        var changed = 0
        for y in stride(from: 0, to: flat.height, by: 4) {
            for x in 0..<(flat.width / 12) where !flat.close(flat[x, y], bent[x, y], 2) { changed += 1 }
        }
        #expect(changed > 1000)
    }
}

/// A frame source whose pictures can be marked new without repainting them.
private final class Bumped: WindowFrameSource, @unchecked Sendable {
    let inner: SyntheticFrames
    var bump: UInt64 = 0
    init(_ inner: SyntheticFrames) { self.inner = inner }
    func latestFrame(for id: WindowID) -> WindowFrame? { inner.latestFrame(for: id) }
    func generation(for id: WindowID) -> UInt64 { inner.generation(for: id) + bump }
}

@Test func framesThatWouldLookTheSameAreSkipped() throws {
    let renderer = try Renderer()
    let layer = CAMetalLayer()
    layer.device = renderer.device
    layer.pixelFormat = Renderer.pixelFormat
    layer.drawableSize = CGSize(width: 756, height: 491)
    var look = Look()
    look.labels = false
    let scene = Fixture.overview(Fixture.retina, look: look)
    let frames = Bumped(SyntheticFrames(windows: scene.windows, scale: 1))
    func draw(_ scene: Scene) throws { renderer.draw(scene, frames: frames, into: try #require(layer.nextDrawable())) }

    #expect(renderer.needsDraw(scene, frames: frames)) // nothing drawn yet
    try draw(scene)
    var later = scene
    later.time += 3
    #expect(!renderer.needsDraw(later, frames: frames)) // only the clock moved
    later.camera.zoom *= 1.01
    #expect(renderer.needsDraw(later, frames: frames))
    frames.bump += 1 // a window has a new picture
    #expect(renderer.needsDraw(scene, frames: frames))
    try draw(scene)
    #expect(!renderer.needsDraw(scene, frames: frames))
    renderer.invalidate(screenID: scene.screen.id)
    #expect(renderer.needsDraw(scene, frames: frames))

    // The search field's caret: steady most of its 1.06 s cycle, fading twice.
    var search = Fixture.overview(Fixture.retina, look: look, hud: Fixture.searchHUD().0)
    search.time = 0.1
    try draw(search)
    search.time = 0.3
    #expect(!renderer.needsDraw(search, frames: frames))
    search.time = 0.48 // fading out
    #expect(renderer.needsDraw(search, frames: frames))
    try draw(search)
    search.time = 0.8 // off
    #expect(renderer.needsDraw(search, frames: frames))
    try draw(search)
    search.time = 0.9
    #expect(!renderer.needsDraw(search, frames: frames))
}

@Test func stillsInTheLiveFormatAreUploadedAsTheyAre() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let ctx = try #require(CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpace(name: CGColorSpace.displayP3)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
    ctx.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!, components: [1, 0, 0, 1])!)
    ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
    let image = try #require(ctx.makeImage())
    let texture = try #require(WindowTextures(device: device).upload(image))
    var pixel = [UInt8](repeating: 0, count: 4)
    texture.getBytes(&pixel, bytesPerRow: 64 * 4, from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0)
    #expect(pixel == [0, 0, 255, 255]) // P3 red stays P3 red, like a live frame (no conversion to sRGB)
}
