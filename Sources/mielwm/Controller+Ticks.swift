import AppKit
import MielCore
import QuartzCore

extension Controller {
    /// The ticks Core needs that no overlay frame sends (moves awaiting confirmation,
    /// the switcher's delay, a window waiting to be parked again).
    func scheduleTicks() {
        let plan = state.tickPlan(overlayShown: overlayShown)
        let keep = switch (tickPlan, plan) {
        case (.none, .none), (.everyFrame, .everyFrame): true
        case let (.once(due), .once(needed)): due <= needed // a tick that comes early only finds nothing to do
        default: false
        }
        if tickTimer != nil || tickPlan == .none, keep { return }
        tickTimer?.invalidate()
        tickTimer = nil
        tickPlan = plan
        let tick: @Sendable (Timer) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if case .once = self.tickPlan { (self.tickTimer, self.tickPlan) = (nil, .none) } // a one-shot, done: replaced timers never fire
                self.input(.tick(CACurrentMediaTime()))
            }
        }
        let timer: Timer
        switch plan {
        case .none: return
        case .everyFrame: timer = Timer(timeInterval: 1.0 / 60, repeats: true, block: tick)
        case let .once(at): timer = Timer(timeInterval: max(0, at - CACurrentMediaTime()) + 0.002, repeats: false, block: tick)
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }
}
