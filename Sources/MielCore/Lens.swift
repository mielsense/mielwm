import CoreGraphics
import Foundation

// The barrel lens of shaders/barrel.frag, as positions. With
//   progress = lensEnabled ? transition ^ lensTransitionPower : 0
//   k        = lensStrength * progress          (shader uniform `distort`)
//   e        = 1 + (lensEdgeScale - 1) * progress (uniform `contrast`)
// a screen point p in a screen of size s maps to the source point
//   c  = p / s * 2 - 1                (both axes in -1...1)
//   c' = c * (1 + k * |c|^2) / e
//   source = (c' * 0.5 + 0.5) * s
// which is the shader's `warped`.

/// How far the lens has eased in for an overview transition (0...1).
public func lensProgress(look: Look, transition: Double) -> Double {
    guard look.lensEnabled, transition > 0 else { return 0 }
    return pow(min(transition, 1), look.lensTransitionPower)
}

/// The point of the unlensed image that the lens shows at `screenPoint`
/// (screen-local points, top-left origin). Use it to hit-test the pointer.
public func lensSourcePoint(_ screenPoint: CGPoint, screenSize: CGSize, look: Look,
                            transition: Double) -> CGPoint {
    let progress = lensProgress(look: look, transition: transition)
    guard progress > 0, screenSize.width > 0, screenSize.height > 0 else { return screenPoint }
    let k = look.lensStrength * progress
    let e = 1 + (look.lensEdgeScale - 1) * progress
    let cx = screenPoint.x / screenSize.width * 2 - 1
    let cy = screenPoint.y / screenSize.height * 2 - 1
    let f = (1 + k * (cx * cx + cy * cy)) / max(e, 0.001)
    return CGPoint(x: (cx * f * 0.5 + 0.5) * screenSize.width, y: (cy * f * 0.5 + 0.5) * screenSize.height)
}

/// Inverse of `lensSourcePoint`: where on the screen the lens draws a point
/// of the unlensed image.
public func lensScreenPoint(_ sourcePoint: CGPoint, screenSize: CGSize, look: Look,
                            transition: Double) -> CGPoint {
    let progress = lensProgress(look: look, transition: transition)
    guard progress > 0, screenSize.width > 0, screenSize.height > 0 else { return sourcePoint }
    let k = look.lensStrength * progress
    let e = max(1 + (look.lensEdgeScale - 1) * progress, 0.001)
    let sx = sourcePoint.x / screenSize.width * 2 - 1
    let sy = sourcePoint.y / screenSize.height * 2 - 1
    let target = (sx * sx + sy * sy).squareRoot() * e // r * (1 + k r^2) = target
    guard target > 0 else { return sourcePoint }
    var r = target
    for _ in 0 ..< 20 { // Newton on r + k r^3 - target
        let d = 1 + 3 * k * r * r
        guard abs(d) > 1e-9 else { break }
        r -= (r + k * r * r * r - target) / d
    }
    let scale = r * e / target // c points the same way as s, with length r = |s| * scale
    return CGPoint(x: (sx * scale * 0.5 + 0.5) * screenSize.width, y: (sy * scale * 0.5 + 0.5) * screenSize.height)
}
