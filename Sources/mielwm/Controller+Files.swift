import AppKit
import MielCore
import MielRender
import MielSystem
import QuartzCore

extension Controller {
    func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.saveNow() } }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// layout.json, also what the crash watcher unparks from.
    func saveNow() {
        saveWork?.cancel()
        if state.layoutRevision != savedLayoutRevision {
            let snapshot = LayoutSnapshot(state)
            do {
                if snapshot != savedLayout { try snapshot.save(to: layoutURL) } // a move and back is no change
                savedLayout = snapshot
                savedLayoutRevision = state.layoutRevision
            } catch { log("cannot save the layout: \(error)") }
        }
    }

    func checkConfig() {
        let now = paths.configModified
        guard now != configStamp else { return }
        configStamp = now
        reloadConfig()
    }

    func reloadConfig() {
        let loaded = loadSettings(paths)
        configStamp = paths.configModified
        configErrors = loaded.errors
        for e in configErrors { log("config: \(e)") }
        if loaded.settings != state.settings { input(.setSettings(loaded.settings)) }
        updateMouse()
        loadWallpapers()
        onChange?()
    }
}
