import AppKit
import MielCore

public enum Displays {
    /// Every display in global y-down points. Call on the main thread.
    public static func screens() -> [ScreenInfo] {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSScreen.screens.map { screen in
            let id = screen.displayID
            return ScreenInfo(id: id, name: screen.localizedName,
                              frame: toYDown(screen.frame, primaryHeight: primaryHeight),
                              visibleFrame: toYDown(screen.visibleFrame, primaryHeight: primaryHeight),
                              scale: screen.backingScaleFactor,
                              safeAreaTop: screen.safeAreaInsets.top,
                              isBuiltIn: CGDisplayIsBuiltin(id) != 0)
        }
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
