import AppKit
import MielCore

public enum Displays {
    /// Every display in global y-down points, with the status bar on each.
    /// Reads the window list: call on the main thread, and not on every event.
    public static func screens() -> [ScreenInfo] {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let windows = barWindows()
        return NSScreen.screens.map { screen in
            let id = screen.displayID
            var info = ScreenInfo(id: id, name: screen.localizedName,
                                  frame: toYDown(screen.frame, primaryHeight: primaryHeight),
                                  visibleFrame: toYDown(screen.visibleFrame, primaryHeight: primaryHeight),
                                  scale: screen.backingScaleFactor,
                                  safeAreaTop: screen.safeAreaInsets.top,
                                  isBuiltIn: CGDisplayIsBuiltin(id) != 0)
            info.topBar = topBar(among: windows, on: info)
            return info
        }
    }

    /// Other apps' windows outside the normal layer and the menu bar: where a
    /// status bar would be. Global y-down points. Desktop windows stay in:
    /// Barik's is one, and the others are too tall to pass for a bar.
    static func barWindows() -> [(owner: String, frame: CGRect)] {
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let own = getpid(), menuBar = Int(CGWindowLevelForKey(.mainMenuWindow))
        let barik = Set(NSWorkspace.shared.runningApplications.filter { BarikLink.bundleIDs.contains($0.bundleIdentifier ?? "") }.map(\.processIdentifier))
        var barikHeight: Double?
        return list.compactMap { w in
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                  let layer = w[kCGWindowLayer as String] as? Int, layer != 0, layer != menuBar,
                  let bounds = w[kCGWindowBounds as String] as? NSDictionary, var frame = CGRect(dictionaryRepresentation: bounds)
            else { return nil }
            // Barik's window covers its whole display and draws the bar at the top, as tall as its config says.
            if barik.contains(pid), frame.height > 80 {
                if barikHeight == nil { barikHeight = Self.barikHeight() }
                frame.size.height = barikHeight ?? frame.height
            }
            return (w[kCGWindowOwnerName as String] as? String ?? "", frame)
        }
    }

    private static func barikHeight() -> Double {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let text = BarikConfig.candidates(home: home).lazy.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.first ?? ""
        return BarikConfig.barHeight(text, menuBar: NSStatusBar.system.thickness)
    }

    /// AppKit rects grow upward from the primary display's bottom-left; the
    /// contract's grow downward from its top-left.
    static func toYDown(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
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
