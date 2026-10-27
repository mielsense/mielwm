import Metal
import MetalPerformanceShaders
import MielCore

extension Renderer {
    func prepareWallpaper(_ s: ScreenState, look: Look, width: Int, height: Int, scale: CGFloat, commandBuffer cb: MTLCommandBuffer) {
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
}
