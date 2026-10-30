import CoreVideo
import Metal
import MielCore

/// Everything kept per display between frames.
final class ScreenState {
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

    var markers = [SIMD4<Float>](repeating: .zero, count: 64)
    var markerDims = [Float](repeating: 0, count: 64)

    /// What the last drawable showed (its time zeroed), to skip frames that would look the same.
    var drawn: (scene: Scene, generations: [UInt64])?

    init() {
        worldPass.colorAttachments[0].loadAction = .clear
        worldPass.colorAttachments[0].storeAction = .store
        worldPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        lensPass.colorAttachments[0].loadAction = .dontCare
        lensPass.colorAttachments[0].storeAction = .store
    }
}

struct LabelKey: Hashable {
    var title: String
    var bundleID: String?
}

struct LabelEntry {
    var texture: MTLTexture
    var lastUsed: UInt64
}
