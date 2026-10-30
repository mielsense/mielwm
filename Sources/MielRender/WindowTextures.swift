import CoreVideo
import Metal
import MielCore

// Window images as Metal textures. Live ScreenCaptureKit frames are wrapped
// without a copy through CVMetalTextureCache; stills are uploaded once per
// generation.

final class WindowTextures {
    private struct Entry {
        var source: ObjectIdentifier
        var generation: UInt64
        var texture: MTLTexture
        var cvTexture: CVMetalTexture?
        var lastUsed: UInt64
    }

    private let device: MTLDevice
    private var cache: CVMetalTextureCache?
    private var entries: [WindowID: Entry] = [:]

    init(device: MTLDevice) {
        self.device = device
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
    }

    /// The window's texture, plus the CoreVideo wrapper the caller must keep
    /// alive until the GPU is done with this frame. Keeps showing the last
    /// image when the source has none.
    func texture(for id: WindowID, source: WindowFrameSource, frame: UInt64) -> (MTLTexture, CVMetalTexture?)? {
        let sourceID = ObjectIdentifier(source)
        let generation = source.generation(for: id)
        let current = entries[id].map { $0.source == sourceID && $0.generation == generation } ?? false
        if !current, let image = source.latestFrame(for: id), let (texture, cv) = make(image) {
            entries[id] = Entry(source: sourceID, generation: generation, texture: texture, cvTexture: cv, lastUsed: frame)
        }
        guard entries[id] != nil else { return nil }
        entries[id]!.lastUsed = frame
        return (entries[id]!.texture, entries[id]!.cvTexture)
    }

    func removeAll() {
        entries = [:]
        if let cache { CVMetalTextureCacheFlush(cache, 0) }
    }

    /// Drops textures of windows not drawn for a while.
    func prune(frame: UInt64) {
        guard frame % 120 == 0 else { return }
        entries = entries.filter { frame - $0.value.lastUsed < 600 }
        if let cache { CVMetalTextureCacheFlush(cache, 0) }
    }

    private func make(_ frame: WindowFrame) -> (MTLTexture, CVMetalTexture?)? {
        switch frame {
        case let .pixelBuffer(buffer):
            // Expects kCVPixelFormatType_32BGRA, which is what System asks ScreenCaptureKit for.
            guard let cache, CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
            var cv: CVMetalTexture?
            CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, .bgra8Unorm,
                                                      CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &cv)
            guard let cv, let texture = CVMetalTextureGetTexture(cv) else { return nil }
            return (texture, cv)
        case let .image(image):
            return upload(image).map { ($0, nil) }
        }
    }

    func upload(_ image: CGImage) -> MTLTexture? {
        // Already 8-bit BGRA, premultiplied (the stills System makes): the bytes as they are, like a live frame.
        if image.bitsPerComponent == 8, image.bitsPerPixel == 32,
           image.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue == CGBitmapInfo.byteOrder32Little.rawValue,
           image.alphaInfo == .premultipliedFirst,
           let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: image.width, height: image.height, mipmapped: false)
            desc.usage = .shaderRead
            desc.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: desc) else { return nil }
            texture.replace(region: MTLRegionMake2D(0, 0, image.width, image.height), mipmapLevel: 0, withBytes: bytes, bytesPerRow: image.bytesPerRow)
            return texture
        }
        guard let bitmap = Bitmap(width: image.width, height: image.height) else { return nil }
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bitmap.texture(device: device)
    }
}
