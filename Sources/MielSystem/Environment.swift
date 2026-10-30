import AppKit
import ApplicationServices

/// AeroSpace tiles every new window and fights our moves; mielwm manages
/// nothing while it runs.
public enum AeroSpace {
    public static let bundleID = "bobko.aerospace"

    /// By bundle id only: mielwm's own helper for Barik is also called AeroSpace.
    public static func running() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
    }

    /// Asks AeroSpace to quit, like its own quit command. False if it is not running.
    @discardableResult
    public static func terminate() -> Bool {
        running()?.terminate() ?? false
    }
}

/// The two permissions mielwm needs, and asking for them.
public enum Permissions {
    /// Accessibility, for moving windows and the event tap. `prompt` shows
    /// the system dialog that leads to System Settings.
    public static func accessibility(prompt: Bool = false) -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": prompt] as CFDictionary)
    }

    /// Screen Recording, for window images. `request` asks once; macOS only
    /// applies a new grant after the app restarts.
    public static func screenRecording(request: Bool = false) -> Bool {
        CGPreflightScreenCaptureAccess() || (request && CGRequestScreenCaptureAccess())
    }
}
