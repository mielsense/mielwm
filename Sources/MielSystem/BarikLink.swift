import AppKit
import MielCore

/// What `BarikLink` needs from macOS. Tests stand in for it, so they run
/// without Barik or the helper.
@MainActor
public protocol BarikApps: AnyObject {
    /// When the running Barik started, nil when it isn't running.
    func barikLaunched() -> Date?
    /// Quits a running Barik, waits until it has, and opens it again.
    func relaunchBarik()
    /// Starts the helper; `started` gets its start time, nil if it failed.
    func startHelper(_ url: URL, started: @escaping @MainActor (Date?) -> Void)
    func stopHelper()
}

/// Barik shows mielwm's workspaces (docs/compatible-apps.md). It looks for a
/// running app called AeroSpace once, when it starts, then runs the command
/// at `aerospace.path` in its config. So: point that at mielwm's `aerospace`
/// command, keep the AeroSpace helper running, and relaunch Barik.
@MainActor
public final class BarikLink {
    /// Why the link could not be turned on.
    public enum Problem: Error, Equatable {
        case unsupported(String) // aerospace is set in a form mielwm doesn't edit
        case temporaryLocation // mielwm runs from a place gone at quit; Barik would call a dead path
    }

    /// BarikEnhanced, then upstream Barik.
    nonisolated static let bundleIDs = ["com.mateocerquetella.BarikEnhanced", "Pansy.Barik"]
    static let previousKey = "barikPreviousPath" // aerospace.path as it was, in TOML

    let home: URL, shim: String, helper: URL, apps: BarikApps, defaults: UserDefaults

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, shim: String, helper: URL,
                apps: BarikApps, defaults: UserDefaults = .standard) {
        (self.home, self.shim, self.helper, self.apps, self.defaults) = (home, shim, helper, apps, defaults)
    }

    /// Translocated by macOS (run from Downloads), or on a read-only disk like the DMG. An Applications
    /// folder on a writable external drive is fine.
    public var temporaryLocation: Bool {
        if shim.contains("/AppTranslocation/") { return true }
        guard shim.hasPrefix("/Volumes/") else { return false }
        let readOnly = try? URL(fileURLWithPath: shim).resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly
        return readOnly ?? true // can't tell: don't point Barik at it
    }

    /// The file Barik reads, nil before Barik has made one.
    public var config: URL? {
        BarikConfig.candidates(home: home).first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Starts the helper, so apps that run the `aerospace` command see mielwm.
    /// When Barik has a config, points it at mielwm and relaunches a running Barik.
    public func turnOn() throws {
        guard !temporaryLocation else { throw Problem.temporaryLocation }
        let file = config
        if let file {
            let text = try String(contentsOf: file, encoding: .utf8)
            guard let edited = BarikConfig.pointing(text, to: shim) else { throw Problem.unsupported(file.path) }
            if edited.text != text {
                let backup = URL(fileURLWithPath: file.path + ".mielwm-backup")
                if !FileManager.default.fileExists(atPath: backup.path) {
                    try Data(text.utf8).write(to: backup, options: .withoutOverwriting)
                }
                try write(edited.text, to: file)
                // Another copy's command: the user's own value is the one saved then.
                if !edited.wasMielwm { defaults.set(edited.previous, forKey: Self.previousKey) }
            }
        }
        apps.startHelper(helper) { [apps] _ in if file != nil { apps.relaunchBarik() } }
    }

    /// Puts Barik's old aerospace.path back, stops the helper and relaunches a
    /// running Barik. When the config can't be restored, throws and leaves the helper running.
    /// Without a config there is nothing to put back, and Barik is left alone.
    public func turnOff() throws {
        let file = config
        if let file {
            let text = try String(contentsOf: file, encoding: .utf8)
            let restored = BarikConfig.restoring(text, from: shim, previous: defaults.string(forKey: Self.previousKey))
            if restored != text { try write(restored, to: file) }
            defaults.removeObject(forKey: Self.previousKey)
        }
        apps.stopHelper()
        if file != nil { apps.relaunchBarik() }
    }

    /// mielwm started with the switch on: point Barik at this copy of mielwm
    /// if it names another, start the helper, and relaunch Barik if it
    /// started first and so did not see either. A copy gone at quit leaves
    /// the path alone: any copy's command reaches the running mielwm.
    public func resume() {
        do {
            if !temporaryLocation, let file = config {
                let text = try String(contentsOf: file, encoding: .utf8)
                if let edited = BarikConfig.pointing(text, to: shim), edited.wasMielwm, edited.text != text {
                    try write(edited.text, to: file)
                }
            }
        } catch {
            log("Barik's config was not pointed at this mielwm: \(error)")
        }
        apps.startHelper(helper) { [apps] started in
            if let started, let barik = apps.barikLaunched(), barik < started { apps.relaunchBarik() }
        }
    }

    /// In place, through a symlink: Barik watches the file it opened.
    private func write(_ text: String, to file: URL) throws {
        try Data(text.utf8).write(to: file.resolvingSymlinksInPath())
    }
}

/// The real apps.
@MainActor
public final class SystemBarikApps: BarikApps {
    private var helper: NSRunningApplication?

    public init() {}

    private func barik() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { BarikLink.bundleIDs.contains($0.bundleIdentifier ?? "") }
    }

    public func barikLaunched() -> Date? {
        barik().map { $0.launchDate ?? .distantPast }
    }

    public func relaunchBarik() {
        guard let app = barik(), let url = app.bundleURL else { return }
        app.terminate()
        Task { @MainActor in
            for _ in 0 ..< 50 { // 5 s
                guard app.isTerminated else {
                    try? await Task.sleep(for: .milliseconds(100))
                    continue
                }
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                NSWorkspace.shared.openApplication(at: url, configuration: config) { @Sendable _, error in
                    if let error { log("Barik did not open again: \(error)") }
                }
                return
            }
            log("Barik did not quit; quit and open it yourself")
        }
    }

    public func startHelper(_ url: URL, started: @escaping @MainActor (Date?) -> Void) {
        stopHelper()
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        config.createsNewApplicationInstance = true
        config.arguments = ["--mielwm-pid", String(getpid())] // it quits when mielwm does
        NSWorkspace.shared.openApplication(at: url, configuration: config) { @Sendable app, error in
            Task { @MainActor in
                if let error { log("AeroSpace helper did not start: \(error)") }
                self.helper = app
                started(app.map { $0.launchDate ?? Date() })
            }
        }
    }

    /// SIGTERM: the helper has no run loop that would take a Quit event.
    public func stopHelper() {
        if let pid = helper?.processIdentifier { kill(pid, SIGTERM) }
        helper = nil
    }
}
