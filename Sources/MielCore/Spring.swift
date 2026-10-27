import CoreGraphics
import Foundation

/// How the camera moves between two views.
public enum CameraCurve: String, Codable, Sendable {
    /// Critically damped spring: no overshoot, and a retarget mid-flight keeps
    /// the current velocity, so interrupted flights never jerk.
    case spring
    /// Phantomat's overview curve, cubic-bezier(0.22, 1.0, 0.36, 1.0). A
    /// retarget restarts the curve from where the camera is.
    case bezier
}

/// One animated number.
struct AnimatedValue: Hashable, Sendable {
    var value: Double
    var target: Double
    var velocity = 0.0
    var from: Double // bezier start
    var start = 0.0 // bezier start time

    init(_ value: Double) {
        self.value = value
        target = value
        from = value
    }

    mutating func retarget(_ to: Double, now: Double) {
        guard to != target else { return }
        target = to
        from = value
        start = now
    }

    mutating func warp(_ to: Double) {
        value = to
        target = to
        from = to
        velocity = 0
    }

    /// Exact solution of x'' = -w^2 x - 2w x' over dt, stable for any frame time.
    mutating func springStep(_ dt: Double, omega: Double) {
        let x0 = value - target
        let k = velocity + omega * x0
        let e = exp(-omega * dt)
        value = target + (x0 + k * dt) * e
        velocity = (velocity - omega * k * dt) * e
    }

    mutating func bezierStep(now: Double, duration: Double) {
        let t = duration <= 0 ? 1 : min(1, max(0, (now - start) / duration))
        value = t >= 1 ? target : from + (target - from) * overviewBezier(t)
        velocity = 0
    }

    func settled(_ tolerance: Double) -> Bool {
        abs(value - target) < tolerance && abs(velocity) < tolerance * 20
    }
}

/// cubic-bezier(0.22, 1.0, 0.36, 1.0): y for an x in 0...1.
func overviewBezier(_ x: Double) -> Double {
    let (x1, y1, x2, y2) = (0.22, 1.0, 0.36, 1.0)
    func bez(_ t: Double, _ a: Double, _ b: Double) -> Double {
        3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t
    }
    // x(t) is monotonic for these points: bisect.
    var lo = 0.0, hi = 1.0
    for _ in 0 ..< 40 {
        let mid = (lo + hi) / 2
        if bez(mid, x1, x2) < x { lo = mid } else { hi = mid }
    }
    return bez((lo + hi) / 2, y1, y2)
}

/// The camera and the overview transition, animated together. Zoom moves in
/// log space so zooming in and out feel the same speed. Time is injected.
public struct CameraAnimator: Hashable, Sendable {
    public var curve: CameraCurve
    /// Flight length in seconds: the bezier's duration; the spring's stiffness
    /// is chosen so it is visually done by then.
    public var duration: Double
    public var enabled = true
    var x, y, logZoom, progress: AnimatedValue
    var time: Double

    public init(camera: Camera, transition: Double = 0, now: Double = 0,
                curve: CameraCurve = .spring, duration: Double = 0.8) {
        x = AnimatedValue(camera.center.x)
        y = AnimatedValue(camera.center.y)
        logZoom = AnimatedValue(log(camera.zoom))
        progress = AnimatedValue(transition)
        time = now
        self.curve = curve
        self.duration = duration
    }

    public var camera: Camera {
        Camera(center: CGPoint(x: x.value, y: y.value), zoom: exp(logZoom.value))
    }

    public var target: Camera {
        Camera(center: CGPoint(x: x.target, y: y.target), zoom: exp(logZoom.target))
    }

    public var transition: Double { progress.value }
    public var targetTransition: Double { progress.target }

    public var isSettled: Bool {
        x.settled(0.05) && y.settled(0.05) && logZoom.settled(1e-4) && progress.settled(1e-3)
    }

    /// Flies to `camera` (and the transition, if given) from wherever the
    /// camera is now. `velocity` (canvas points per second) seeds a momentum flight.
    public mutating func fly(to camera: Camera, transition: Double? = nil, now: Double,
                             velocity: CGVector? = nil) {
        step(to: now)
        guard enabled else { return warp(to: camera, transition: transition, now: now) }
        x.retarget(camera.center.x, now: now)
        y.retarget(camera.center.y, now: now)
        logZoom.retarget(log(camera.zoom), now: now)
        if let transition { progress.retarget(transition, now: now) }
        if let velocity, curve == .spring {
            x.velocity = velocity.dx
            y.velocity = velocity.dy
        }
    }

    /// Jumps there with no animation (drag, pan, pinch).
    public mutating func warp(to camera: Camera, transition: Double? = nil, now: Double) {
        x.warp(camera.center.x)
        y.warp(camera.center.y)
        logZoom.warp(log(camera.zoom))
        if let transition { progress.warp(transition) }
        time = now
    }

    public mutating func step(to now: Double) {
        let dt = now - time
        time = now
        guard dt > 0 else { return }
        let omega = 12 / max(duration, 0.01)
        for path in [\CameraAnimator.x, \.y, \.logZoom, \.progress] {
            switch curve {
            case .spring: self[keyPath: path].springStep(dt, omega: omega)
            case .bezier: self[keyPath: path].bezierStep(now: now, duration: duration)
            }
        }
        if isSettled {
            for path in [\CameraAnimator.x, \.y, \.logZoom, \.progress] {
                self[keyPath: path].warp(self[keyPath: path].target)
            }
        }
    }
}
