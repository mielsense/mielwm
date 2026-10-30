import AppKit
import MielCore

extension Controller {
    func system(_ event: SystemEvent) {
        if case let .windowClosed(id) = event { capture.stop([id], dropFrames: true) }
        input(.system(event))
        if case .screensChanged = event {
            rebuildOverlays()
            onScreens?()
        }
    }

    /// The system's accent, appearance, accessibility options and glass, as Core needs them;
    /// previews pass their own appearance and options.
    static func applySystemLook(to state: inout CanvasState, dark: Bool? = nil, accessibility: AccessibilityOptions? = nil) {
        state.systemAccent = systemAccent()
        state.systemDark = dark ?? systemDark()
        state.accessibility = accessibility ?? Self.accessibility()
        state.liquidGlassAvailable = liquidGlassAvailable
    }

    static func systemAccent() -> RGB? {
        NSColor.controlAccentColor.usingColorSpace(.sRGB).map { RGB(Double($0.redComponent), Double($0.greenComponent), Double($0.blueComponent)) }
    }

    /// Reduce Motion, Reduce Transparency and Increase Contrast from System Settings › Accessibility › Display.
    static func accessibility() -> AccessibilityOptions {
        let w = NSWorkspace.shared
        return AccessibilityOptions(reduceMotion: w.accessibilityDisplayShouldReduceMotion,
                                    reduceTransparency: w.accessibilityDisplayShouldReduceTransparency,
                                    increaseContrast: w.accessibilityDisplayShouldIncreaseContrast)
    }

    /// Liquid glass came with macOS 26.
    nonisolated static var liquidGlassAvailable: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    static func systemDark() -> Bool {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// The user and host names, so the tidy-up does not group windows by them.
    static func stopwords() -> Set<String> {
        var host = [CChar](repeating: 0, count: 256)
        gethostname(&host, host.count)
        let words = [NSUserName(), String(cString: host)].flatMap { $0.lowercased().split { !$0.isLetter && !$0.isNumber } }
        return Set(words.map(String.init).filter { $0.count > 1 && $0 != "local" })
    }
}
