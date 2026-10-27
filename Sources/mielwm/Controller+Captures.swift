import AppKit
import MielCore
import MielRender
import MielSystem
import QuartzCore

extension Controller {
    func openGate(_ input: CoreInput, opensOverview: Bool) {
        warmStreams()
        let waitFor = state.focused.flatMap { f in state.window(f).flatMap { $0.isShown && !$0.parked ? f : nil } }
        let timeout = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.closeGate() } }
        gate = ([input], waitFor, opensOverview, timeout)
        updateTap() // keys typed meanwhile wait in the gate too
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.openBudget, execute: timeout)
    }

    private func closeGate() {
        guard let g = gate else { return }
        g.timeout.cancel()
        gate = nil
        g.queue.forEach(input)
        updateTap()
    }

    func firstFrame(_ id: WindowID) {
        if let g = gate, g.waitFor == nil || g.waitFor == id { closeGate() }
    }

    /// Live streams for the windows on screen (the focused and largest
    /// first, at most `maxStreams`), fresh stills for the rest.
    /// Called on the overview chord's modifiers, ⌥Tab and before the overlay opens.
    func warmStreams() {
        guard renderer != nil else { return }
        coolWork?.cancel()
        coolWork = nil
        capture.setRate(.overview)
        let onScreen = state.windows.filter { $0.isShown && !$0.parked }.sorted {
            ($0.id == state.focused ? 1 : 0, $0.real.width * $0.real.height) > ($1.id == state.focused ? 1 : 0, $1.real.width * $1.real.height)
        }
        for w in onScreen.prefix(Self.maxStreams) {
            let scale = screenShowingMost(w.real, of: state.screens)?.scale ?? 2
            capture.warm([w.id], maxPixelSize: CGSize(width: w.real.width * scale, height: w.real.height * scale))
        }
        if !streamsLive {
            capture.captureStills(state.windows.filter { $0.isShown && $0.parked }.map(\.id) + onScreen.dropFirst(Self.maxStreams).map(\.id),
                                  scale: stillScale)
        }
        streamsLive = true
        if !overlayShown { scheduleCool() }
    }

    func scheduleCool() {
        coolWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.overlayShown, self.gate == nil else { return }
                self.capture.cool(stillScale: self.stillScale) // small stills of the last frames stay for next time
                self.capture.setRate(.idle)
                self.streamsLive = false
            }
        }
        coolWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.streamLinger, execute: work)
    }

    /// Stills at the size the overview draws them.
    var stillScale: CGFloat { min(1, max(0.5, state.settings.initialZoom)) }
}
