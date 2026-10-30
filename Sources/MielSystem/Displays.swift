import AppKit
import MielCore

/// The displays macOS reports, as Core's `ScreenInfo`.
public enum Displays {
    /// Every display in global y-down points, with the status bar on each.
    /// A display in a full screen Space keeps its bar from `previous`.
    /// Reads the window list: call on the main thread, and not on every event.
    public static func screens(keeping previous: [ScreenInfo] = []) -> [ScreenInfo] {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let (windows, normal) = barWindows()
        return NSScreen.screens.map { screen in
            let id = screen.displayID
            var info = ScreenInfo(id: id, name: screen.localizedName,
                                  frame: toYDown(screen.frame, primaryHeight: primaryHeight),
                                  visibleFrame: toYDown(screen.visibleFrame, primaryHeight: primaryHeight),
                                  scale: screen.backingScaleFactor,
                                  safeAreaTop: screen.safeAreaInsets.top,
                                  isBuiltIn: CGDisplayIsBuiltin(id) != 0)
            info.topBar = topBar(among: windows, on: info, filledBy: normal, previous: previous.first { $0.id == id }?.topBar)
            return info
        }
    }

    /// Other apps' windows outside the normal layer and the menu bar, where a
    /// status bar would be, and the frames of normal ones. Global y-down
    /// points. Desktop windows stay in: Barik's is one, and the others are too
    /// tall to pass for a bar.
    static func barWindows() -> (bars: [(owner: String, frame: CGRect)], normal: [CGRect]) {
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return ([], []) }
        let own = getpid(), menuBar = Int(CGWindowLevelForKey(.mainMenuWindow))
        let barik = Set(NSWorkspace.shared.runningApplications.filter { BarikLink.bundleIDs.contains($0.bundleIdentifier ?? "") }.map(\.processIdentifier))
        var barikHeight: Double?, normal: [CGRect] = []
        let bars = list.compactMap { w -> (owner: String, frame: CGRect)? in
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                  let layer = w[kCGWindowLayer as String] as? Int, layer != menuBar,
                  let bounds = w[kCGWindowBounds as String] as? NSDictionary, var frame = CGRect(dictionaryRepresentation: bounds)
            else { return nil }
            guard layer != 0 else {
                normal.append(frame)
                return nil
            }
            // Barik's window covers its whole display and draws the bar at the top, as tall as its config says.
            if barik.contains(pid), frame.height > 80 {
                if barikHeight == nil { barikHeight = Self.barikHeight() }
                frame.size.height = barikHeight ?? frame.height
            }
            return (w[kCGWindowOwnerName as String] as? String ?? "", frame)
        }
        return (bars, normal)
    }

    private static func barikHeight() -> Double {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let text = BarikConfig.candidates(home: home).lazy.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.first ?? ""
        return BarikConfig.barHeight(text, menuBar: NSStatusBar.system.thickness)
    }

    /// AppKit rects grow upward from the primary display's bottom-left; the
    /// contract's grow downward from its top-left.
    public static func toYDown(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// True when "Displays have separate Spaces" is off. The key is unset by
    /// default, which means separate Spaces are on.
    public static func spansDisplays() -> Bool {
        UserDefaults(suiteName: "com.apple.spaces")?.bool(forKey: "spans-displays") ?? false
    }
}

public extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
