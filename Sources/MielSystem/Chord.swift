import Carbon.HIToolbox
import MielCore

/// A physical key plus exact modifiers. Key codes are positions on an ANSI
/// keyboard, like AeroSpace's default qwerty mapping.
public struct Chord: Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(_ keyCode: UInt16, _ modifiers: Modifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// The key a config chord names, at its ANSI position.
    public init?(_ chord: KeyChord) {
        guard let code = keyCodes[chord.key] else { return nil }
        self.init(code, chord.modifiers)
    }

    /// The key code of a key name in `KeyChord`'s spelling.
    public static func keyCode(_ name: String) -> UInt16? { keyCodes[name] }
}

/// Every name in `KeyChord.allKeys`.
private let keyCodes: [String: UInt16] = {
    var map: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
        "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
        "tab": kVK_Tab, "return": kVK_Return, "escape": kVK_Escape, "space": kVK_Space,
        "delete": kVK_Delete, "forwarddelete": kVK_ForwardDelete,
        "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
        "minus": kVK_ANSI_Minus, "equal": kVK_ANSI_Equal, "comma": kVK_ANSI_Comma, "period": kVK_ANSI_Period,
        "slash": kVK_ANSI_Slash, "semicolon": kVK_ANSI_Semicolon, "quote": kVK_ANSI_Quote,
        "backslash": kVK_ANSI_Backslash, "grave": kVK_ANSI_Grave,
        "leftbracket": kVK_ANSI_LeftBracket, "rightbracket": kVK_ANSI_RightBracket,
    ]
    let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
    for (i, code) in functionKeys.enumerated() { map["f\(i + 1)"] = code }
    return map.mapValues { UInt16($0) }
}()

/// What the tap consumes. Built on the main thread, swapped in whole.
public struct BindingTable: Equatable, Sendable {
    public var bindings: [Chord: Action]
    /// Consumed and dropped, so they never reach apps.
    public var swallow: Set<Chord>

    public init(bindings: [Chord: Action] = [:], swallow: Set<Chord> = BindingTable.optionNoOps) {
        self.bindings = bindings
        self.swallow = swallow
    }

    /// "Do nothing" keys in their AeroSpace positions: ⌥1-0, ⌥⇧1-0, ⌥/, ⌥,
    /// and ⌥; would otherwise type ¡™£.
    public static let optionNoOps: Set<Chord> = {
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                      kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0]
        var chords = Set(digits.flatMap { [Chord(UInt16($0), .option), Chord(UInt16($0), [.option, .shift])] })
        for key in [kVK_ANSI_Slash, kVK_ANSI_Comma, kVK_ANSI_Semicolon] { chords.insert(Chord(UInt16(key), .option)) }
        return chords
    }()

    /// Actions that fire again while their key is held.
    public static func repeats(_ action: Action) -> Bool {
        switch action {
        case .nudge, .switchWindow, .pan, .zoomIn, .zoomOut: true
        default: false
        }
    }
}
