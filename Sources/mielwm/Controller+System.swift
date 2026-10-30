import AppKit
import Carbon.HIToolbox
import MielCore

extension Controller {
    /// Keys the overview and switcher understand; nil for typed text.
    static func namedKey(keyCode: UInt16, characters: String, modifiers: Modifiers) -> NamedKey? {
        switch Int(keyCode) {
        case kVK_LeftArrow: return .arrow(.left)
        case kVK_RightArrow: return .arrow(.right)
        case kVK_DownArrow: return .arrow(.down)
        case kVK_UpArrow: return .arrow(.up)
        case kVK_Tab: return .tab
        case kVK_Return, kVK_ANSI_KeypadEnter: return .enter
        case kVK_Escape: return .escape
        case kVK_F1: return .f1
        case kVK_Delete: return .backspace
        case kVK_ForwardDelete: return .forwardDelete
        default: break
        }
        guard modifiers.contains(.control) || modifiers.contains(.command) else { return nil }
        let digits = [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        if let n = digits.firstIndex(of: Int(keyCode)) { return .digit(n) }
        if Int(keyCode) == kVK_ANSI_Equal { return .equals }
        if Int(keyCode) == kVK_ANSI_Minus { return .minus }
        return characters.isEmpty ? nil : .character(characters.lowercased())
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
    static var liquidGlassAvailable: Bool {
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
