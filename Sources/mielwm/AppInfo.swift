import AppKit

/// An app by bundle id, as Settings shows it: its name, its icon, and whether it is installed.
struct AppInfo {
    let name: String
    let icon: NSImage
    let installed: Bool
    @MainActor private static var known: [String: AppInfo] = [:] // views ask on every redraw; a lookup reads the disk

    @MainActor init(bundleID: String) {
        if let info = Self.known[bundleID] {
            self = info
            return
        }
        self.init(looking: bundleID)
        if installed { Self.known[bundleID] = self } // an app not found may be installed later
    }

    private init(looking bundleID: String) {
        // The running copy first: Launch Services may know an old one (a renamed backup) under the same id.
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        if let url = running?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            // The app's own name, not the file's: a copy renamed on disk keeps its real name.
            let bundle = Bundle(url: url)
            name = running?.localizedName ?? bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            icon = NSWorkspace.shared.icon(forFile: url.path)
            installed = true
        } else {
            name = bundleID
            icon = NSWorkspace.shared.icon(for: .applicationBundle)
            installed = false
        }
    }
}

extension AppInfo {
    /// The app's icon, or the generic one without a bundle id.
    @MainActor static func icon(for bundleID: String?) -> NSImage {
        bundleID.map { AppInfo(bundleID: $0).icon } ?? NSWorkspace.shared.icon(for: .applicationBundle)
    }
}
