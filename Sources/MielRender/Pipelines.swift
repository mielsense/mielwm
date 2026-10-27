import Metal

/// Pipelines are compiled once per device and shared by every Renderer.
final class Pipelines {
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
