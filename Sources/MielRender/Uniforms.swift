// Swift mirrors of the shader structs in Shaders.swift. Field order and
// padding match the Metal layout (float4 first, then float2, then scalars);
// RenderTests checks the sizes.

import CoreGraphics
import simd

struct QuadUniforms {
    var rect: SIMD4<Float>
    var target: SIMD2<Float>
    var pad = SIMD2<Float>()
}

struct BackdropUniforms {
    var tile = SIMD4<Float>()
    var solid = SIMD4<Float>()
    var gridOrigin = SIMD2<Float>()
    var hasWallpaper: Float = 0
    var blurAlpha: Float = 0
    var dim: Float = 0
    var gridOpacity: Float = 0
    var gridCell: Float = 1
    var gridFine: Float = 0
    var gridMark: Float = 1
    var gridDots: Float = 0
    var pad0: Float = 0
    var pad1: Float = 0
}

struct WindowUniforms {
    var rect = SIMD4<Float>()
    var accent = SIMD4<Float>()
    var dimColor = SIMD4<Float>()
    var placeholder = SIMD4<Float>()
    var radius: Float = 0
    var alpha: Float = 1
    var shadow: Float = 0
    var shadowSigma: Float = 1
    var shadowDrop: Float = 0
    var ringGap: Float = 0
    var ringWidth: Float = 0
    var glow: Float = 0
    var glowRadius: Float = 1
    var outline: Float = 0
    var outlineWidth: Float = 0
    var hasTexture: Float = 0
}

struct SolidUniforms {
    var rect = SIMD4<Float>()
    var fill = SIMD4<Float>()
    var border = SIMD4<Float>()
    var radius: Float = 0
    var borderWidth: Float = 0
    var pad0: Float = 0
    var pad1: Float = 0
}

struct TexturedUniforms {
    var alpha: Float = 1
    var pad0: Float = 0
    var pad1: Float = 0
    var pad2: Float = 0
}

struct LensUniforms {
    var panel = SIMD4<Float>()
    var button = SIMD4<Float>()
    var viewport = SIMD4<Float>()
    var active = SIMD4<Float>()
    var inactive = SIMD4<Float>()
    var panelColor = SIMD4<Float>()
    var hairline = SIMD4<Float>()
    var line = SIMD4<Float>()
    var map = SIMD4<Float>(0, 0, 1, 1) // screen uv to world uv: offset, scale (the world is overscanned)
    var size = SIMD2<Float>()
    var distort: Float = 0
    var contrast: Float = 1
    var feather: Float = 0
    var edgeBlur: Float = 0
    var edgeBlurStart: Float = 0.45
    var vignette: Float = 0
    var chromatic: Float = 0
    var minimapOpacity: Float = 0
    var minimapTransition: Float = 0
    var pixelScale: Float = 1
    var count: Int32 = 0
    var focused: Int32 = -1
    var opacity: Float = 1
    var workspaceCount: Int32 = 0 // outlines in the marker array after the windows
}

struct MaterialUniforms {
    var rect = SIMD4<Float>()
    var map = SIMD4<Float>(0, 0, 1, 1)
    var size = SIMD2<Float>()
    var radius: Float = 0
    var distort: Float = 0
    var contrast: Float = 1
    var alpha: Float = 1
    var blur: Float = 0
    var pad: Float = 0
}

extension SIMD4 where Scalar == Float {
    init(_ r: CGRect) {
        self.init(Float(r.minX), Float(r.minY), Float(r.width), Float(r.height))
    }
}

