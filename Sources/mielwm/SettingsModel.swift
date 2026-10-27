import AppKit
import Combine
import MielCore
import MielSystem
import ServiceManagement
import SwiftUI

/// What the Settings window shows and edits: config.json as Settings. A
/// change reaches the running canvas at once (`onLive`) and config.json a
/// moment later, so a slider being dragged does not write on every step.
@MainActor
final class SettingsModel: ObservableObject {
    let paths: ConfigPaths
    @Published private(set) var settings: MielCore.Settings
    @Published private(set) var errors: [String] // what config.json got wrong
    @Published var problem: String? // a write that failed, shown as an alert
    @Published var recording: ShortcutSlot? { didSet { recordingChanged() } } // the recorder that listens
    @Published var held: Modifiers = [] // modifiers down while recording
    var keyMonitor: Any?
    // View state lives here: the Command Line Tools have no SwiftUI macros, so no @State.
    @Published var pane: SettingsPane {
        didSet {
            scrolled = false
            if remembersPane { UserDefaults.standard.set(pane.rawValue, forKey: "settingsPane") }
        }
    }
    @Published var loginStatus = SMAppService.mainApp.status
    @Published var aeroSpaceFound: AeroSpaceImport?
    @Published var confirmReset = false
    @Published var confirmRestoreShortcuts = false
    @Published var conflict: ShortcutConflict?
    @Published var expanded: Set<ShortcutFamily> = [] // custom families showing their keys
    @Published var scrolled = false // the pane is scrolled: a line under the title bar
    @Published var cliStatus = CLITool.status()
    /// The Appearance pane's canvas, made on the first visit; its GPU textures go when the window closes.
    var preview: AppearancePreview {
        if let madePreview { return madePreview }
        let made = AppearancePreview()
        madePreview = made
        return made
    }
    private(set) var madePreview: AppearancePreview?
    /// After every write: the canvas reloads config.json.
    var onWrite: () -> Void = {}
    /// Every change, before it is written.
    var onLive: (MielCore.Settings) -> Void = { _ in }
    /// While a recorder listens, the canvas's shortcuts must let keys through.
    var onRecording: (Bool) -> Void = { _ in }
    let remembersPane: Bool
    private var pending: [String: SettingValue?] = [:]
    private var flushWork: DispatchWorkItem?
    private var stamp: Date?
    private var watcher: FileWatcher?

    init(paths: ConfigPaths = .standard(), remembersPane: Bool = true) {
        self.paths = paths
        self.remembersPane = remembersPane
        let loaded = loadSettings(paths)
        settings = loaded.settings
        errors = loaded.errors
        pane = remembersPane ? UserDefaults.standard.string(forKey: "settingsPane").flatMap(SettingsPane.init) ?? .general : .general
        stamp = paths.configModified
    }

    /// Picks up edits made elsewhere (the file, the canvas).
    func reload() {
        guard pending.isEmpty else { return }
        stamp = paths.configModified
        let loaded = loadSettings(paths)
        if loaded.settings != settings { settings = loaded.settings }
        if loaded.errors != errors { errors = loaded.errors }
    }

    /// While the window is open, edits to the files show up at once.
    func watch(_ on: Bool) {
        watcher?.stop()
        watcher = nil
        guard on else { return }
        watcher = FileWatcher([paths.config]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.paths.configModified != self.stamp else { return }
                self.reload()
            }
        }
    }

    func set(_ key: String, _ value: SettingValue) {
        guard settings.set(value, forKey: key) == nil else { return }
        pending[key] = Settings.entry(key, value)
        onLive(settings)
        flushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.flush() } }
        flushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// Writes `changes` (and anything waiting) now.
    func apply(_ changes: [String: SettingValue?]) {
        pending.merge(changes) { _, new in new }
        flush()
    }

    func flush() {
        flushWork?.cancel()
        guard !pending.isEmpty else { return }
        do { try updateConfig(pending, paths: paths) } catch { problem = "\(error)" }
        pending = [:]
        reload()
        onWrite()
    }

    /// Puts config.json in the Trash: every setting back to its default.
    func resetAll() {
        flushWork?.cancel()
        pending = [:]
        for url in [paths.config] where FileManager.default.fileExists(atPath: url.path) {
            do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } catch { problem = "\(error.localizedDescription)" }
        }
        reload()
        onWrite()
    }

    // MARK: Bindings for controls

    func flag(_ key: String) -> Binding<Bool> {
        Binding(get: { if case let .flag(b)? = self.settings.value(forKey: key) { b } else { false } },
                set: { self.set(key, .flag($0)) })
    }

    func number(_ key: String) -> Binding<Double> {
        Binding(get: { if case let .number(n)? = self.settings.value(forKey: key) { n } else { 0 } },
                set: { self.set(key, .number($0)) })
    }

    func text(_ key: String) -> Binding<String> {
        Binding(get: { if case let .text(s)? = self.settings.value(forKey: key) { s } else { "" } },
                set: { self.set(key, .text($0)) })
    }
}
