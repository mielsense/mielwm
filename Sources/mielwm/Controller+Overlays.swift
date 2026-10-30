import AppKit
import MielCore
import MielRender
import MielSystem
import QuartzCore

extension Controller {
    func rebuildOverlays() {
        guard let renderer else { return }
        let ids = Set(state.screens.map(\.id))
        for (id, o) in overlays where !ids.contains(id) {
            o.close()
            overlays[id] = nil
        }
        for s in state.screens {
            let o = overlays[s.id] ?? Overlay(screenID: s.id, controller: self, device: renderer.device)
            overlays[s.id] = o
            o.place(on: s)
            renderer.invalidate(screenID: s.id)
            if overlayShown { o.show(key: false) }
        }
        loadWallpapers()
        updateMouse()
    }

    /// Each display's desktop picture, read again only when it is another
    /// file or the file changed (dynamic ones, captured, every time).
    func loadWallpapers() {
        guard renderer != nil else { return }
        for s in state.screens {
            let url = NSScreen.screens.first { $0.displayID == s.id }.flatMap(NSWorkspace.shared.desktopImageURL(for:))
            let date = url.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            let stamp = url.flatMap { $0.pathExtension.lowercased() == "heic" ? nil : "\($0.path) \(date?.timeIntervalSince1970 ?? 0) \(s.frame.size) \(s.scale)" }
            if let stamp, wallpaperStamps[s.id] == stamp { continue }
            wallpaperStamps[s.id] = stamp
            MielSystem.Wallpaper.image(for: s) { [weak self] image in self?.setWallpaper(image, on: s) }
        }
    }

    /// Sets the wallpaper and prepares it (scaled, blurred), so the first
    /// frame of the overview does not pay for that.
    private func setWallpaper(_ image: CGImage?, on screen: ScreenInfo) {
        guard let renderer else { return }
        renderer.setWallpaper(image, screenID: screen.id)
        renderer.prepare(state.scene(for: screen))
        wakeFrames()
    }

    /// Once the overlay has been hidden a while: its GPU memory goes, made
    /// again on the next frame; later the stills of parked windows shrink.
    private func schedulePurge() {
        purgeWork?.cancel()
        shrinkWork?.cancel()
        let purge = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.overlayShown, self.gate == nil else { return }
                self.renderer?.purge()
                for o in self.overlays.values { o.dropDrawables() }
            }
        }
        let shrink = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.overlayShown, self.gate == nil, !self.streamsLive else { return }
                self.capture.shrinkStills(self.state.windows.filter(\.parked).map(\.id))
            }
        }
        purgeWork = purge
        shrinkWork = shrink
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.purgeDelay, execute: purge)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.shrinkDelay, execute: shrink)
    }

    func showOverlays() {
        overlayShown = true
        coolWork?.cancel()
        purgeWork?.cancel()
        shrinkWork?.cancel()
        for o in overlays.values { o.show(key: state.isOverview && o.screenID == state.activeScreen.id) }
        updateMouse()
    }

    func hideOverlays() {
        overlayShown = false
        restingSince = nil
        fadeStart = nil
        for o in overlays.values {
            o.hide()
            renderer?.invalidate(screenID: o.screenID) // shown again, it starts with a fresh frame
        }
        if streamsLive {
            capture.setRate(.linger) // fresh enough should it open again, a quarter of the work
            scheduleCool()
        }
        schedulePurge()
        scheduleTicks()
    }

    func updateMouse() {
        // Open, the overview catches the pointer even when it ignores clicks, so none land on windows behind it.
        for o in overlays.values { o.window.ignoresMouseEvents = !state.isOverview }
    }

    /// One display link frame of one overlay: tick Core, then draw.
    func frame(screenID: UInt32) {
        let now = CACurrentMediaTime()
        if now - state.now > 0.0005 { input(.tick(now)) }
        guard overlayShown else { return }
        if let rest = restingSince, !state.movesInFlight || now - rest > Self.confirmBudget {
            restingSince = nil
            fadeStart = now
        }
        var opacity = 1.0
        if let fade = fadeStart {
            opacity = 1 - (now - fade) / Self.fadeDuration
            if opacity <= 0 { return hideOverlays() }
        }
        guard let renderer, let overlay = overlays[screenID], let screen = screen(id: screenID) else { return }
        var scene = state.scene(for: screen, time: now)
        if !worldShown {
            scene.windows = []
            scene.dropIndicator = nil
        }
        scene.opacity = opacity
        // The HUD shows in native views over the canvas; Metal draws the canvas, the tags and the minimap.
        // A HUD change is an input, and every input wakes paused frames (Controller.state), so this runs for each.
        overlay.chrome.show(ChromeContent(taking: &scene, worldShown: worldShown, toastOpacity: state.notices.toast?.opacity(at: now) ?? 1),
                            transition: scene.transition, opacity: opacity)
        pictureChecks[screenID] = capture.picturesStored // before the look, so a picture landing during it counts as new
        overlay.draw(scene, renderer: renderer, frames: capture)
        // Settled with nothing new to draw on any display: no frames (nor ticks, which would
        // wake them) until an input, a state change or a new picture.
        if overlay.idleFrames > Overlay.idleAfter, !state.needsTicks, restingSince == nil, fadeStart == nil,
           overlays.values.allSatisfy({ $0.idleFrames > Overlay.idleAfter }) {
            for o in overlays.values { o.view.link?.isPaused = true }
            framesPaused = true
            let looked = overlays.keys.compactMap { pictureChecks[$0] }.min() ?? 0 // the display that looked longest ago
            capture.wakeOnNextPicture(after: looked) { [weak self] in self?.wakeFrames() }
        }
    }

    func wakeFrames() {
        framesPaused = false
        guard overlayShown else { return }
        for o in overlays.values { o.wake() }
    }

    func didOpenOverview() {
        guard renderer != nil, mode == .normal else { return }
        NSApp.activate(ignoringOtherApps: true)
        overlays[state.activeScreen.id]?.show(key: true)
        updateMouse()
        // If macOS refuses to activate us, the tap types for the overview instead.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.state.isOverview, !NSApp.isActive else { return }
                self.keyCaptureFallback = true
                self.updateTap()
            }
        }
    }

    func didCloseOverview() {
        keyCaptureFallback = false
        updateMouse()
    }
}
