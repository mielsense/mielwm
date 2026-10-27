// Lens uniforms and minimap pixels for the shader. The geometry itself is
// Core's (lensProgress, lensSourcePoint, minimapLayout), so what is drawn and
// what the app hit-tests come from one place.

import CoreGraphics
import Foundation
import MielCore

/// The lens uniforms for one frame: with `progress` from Core's
/// `lensProgress`, distort = strength * progress and contrast =
/// 1 + (edgeScale - 1) * progress, as in Core's `lensSourcePoint`.
struct LensParameters: Equatable {
    var progress = 0.0
    var distort = 0.0
    var contrast = 1.0
    var feather = 0.0
    var edgeBlur = 0.0
    var edgeBlurStart = 0.45
    var vignette = 0.0
    var chromatic = 0.0

    init(look: Look, transition: Double) {
        edgeBlurStart = look.edgeBlurStart
        progress = lensProgress(look: look, transition: transition)
        guard progress > 0 else { return }
        distort = look.lensStrength * progress
        contrast = 1 + (look.lensEdgeScale - 1) * progress
        feather = look.lensFeather * progress
        edgeBlur = look.edgeBlur * progress
        vignette = look.vignette * progress
        chromatic = look.chromatic * progress
    }

    /// How far past each screen edge the lens reads the world at any
    /// transition, as a fraction of the screen. The world is drawn that much
    /// larger, so the bent corners show canvas, not black. Capped: past it
    /// (extreme settings) the feather fades the edge out.
    static func overscan(_ look: Look) -> Double {
        guard look.lensEnabled else { return 0 }
        let reach = (1 + 2 * look.lensStrength) / max(look.lensEdgeScale, 0.001) // a corner's source, -1...1 space
        guard reach > 1 else { return 0 }
        let spread = look.edgeBlur * 0.02 + look.chromatic * 0.014 // blur taps and the fringe read a little further
        return min((reach - 1) / 2 + look.lensFeather + spread, 0.2)
    }

    /// Same test as the shader's `lens` flag: false means the pass is a plain copy.
    var isIdentity: Bool {
        abs(distort) < 0.000001 && abs(contrast - 1) < 0.000001 && edgeBlur <= 0.0001 && vignette <= 0.0001 && chromatic <= 0.0001
    }
}

/// Core's minimap layout in screen pixels, rounded, with the window markers
/// written into the shader's arrays.
struct MinimapPixels {
    var panel = CGRect.zero
    var button = CGRect.zero
    var viewport = CGRect.zero
    var count = 0 // window markers, first in the arrays
    var workspaceCount = 0 // workspace outlines, after them

    private static func px(_ r: CGRect, _ scale: CGFloat) -> CGRect {
        CGRect(x: (r.minX * scale).rounded(), y: (r.minY * scale).rounded(),
               width: (r.width * scale).rounded(), height: (r.height * scale).rounded())
    }

    /// Writes up to `markers.count` window markers into `markers` (no allocation).
    init?(_ model: MinimapModel, look: Look, screenPx: CGSize, scale: CGFloat, markers: inout [SIMD4<Float>], dims: inout [Float]) {
        guard scale > 0 else { return nil }
        let layout = minimapLayout(screenSize: CGSize(width: screenPx.width / scale, height: screenPx.height / scale), look: look,
                                   windows: model.windows.map(\.frame), viewport: model.viewport, workspaces: model.workspaces)
        guard !layout.worldBounds.isEmpty else { return nil }
        panel = Self.px(layout.panel, scale)
        button = model.showsArrangeButton ? Self.px(layout.arrangeButton, scale) : .zero
        viewport = Self.px(layout.viewport, scale)
        let workspaces = layout.workspaces.prefix(16)
        for (marker, w) in zip(layout.windows, model.windows) where count < markers.count - workspaces.count {
            markers[count] = SIMD4(Self.px(marker, scale))
            // Fully receded windows stay as faint ghosts (alpha 0.22).
            dims[count] = Float(min(max(w.dim, 0), 1) * 0.78)
            count += 1
        }
        for (i, outline) in workspaces.enumerated() { markers[count + i] = SIMD4(Self.px(outline, scale)) }
        workspaceCount = workspaces.count
    }
}
