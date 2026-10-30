import CoreGraphics
import Foundation

/// Everything the user can set. `look` is what Render reads; the rest is
/// behaviour.
public struct Settings: Hashable, Codable, Sendable {
    public var look = Look()
    /// navigator:accent: a preset name, #rrggbb, or "auto" for the system accent.
    public var accent = "auto"

    // canvas:*
    public var initialZoom = 0.72
    var minZoom = 0.05
    var maxZoom = 2.5
    public var zoomStep = 0.12 // wheel zoom strength
    var autoPlace = true
    var placementGap = 40.0
    var snapEnabled = true // snaps to look.gridSize
    var rememberLayout = true
    var arrangeContextGrouping = true
    var arrangeSizeSimilarity = 0.12
    var arrangeResizeLimit = 0.15
    public var gap = 12.0 // Fill keeps this far from the screen edges

    // input:*
    public var panSensitivity = 1.0
    public var dragThreshold = 10.0
    public var scrollFactor = 1.0
    var moveModifier = "ctrl+opt" // held with a left/right drag to move/resize a window
    public var swipeWorkspaces = true // three fingers sideways on the trackpad: next or previous workspace

    // layout:* and gaps:* (AeroSpace's names where it has them)
    public var defaultLayout = LayoutMode.tiles // what a new window joins
    public var orientation = TileOrientation.auto
    public var gapInnerHorizontal = 8.0
    public var gapInnerVertical = 8.0
    public var gapOuterLeft = 12.0
    public var gapOuterRight = 12.0
    public var gapOuterBottom = 12.0
    public var gapOuterTop = 12.0 // the built-in display
    public var gapOuterTopExternal = 54.0 // other displays, in Custom
    public var topGapMode = TopGapMode.auto // gaps:outer_top_external: "auto", "same" or a number (Custom)
    /// Bundle ids that always float, comma separated.
    public var floatingApps = "com.apple.systempreferences,com.apple.ActivityMonitor,com.apple.calculator,com.apple.archiveutility"
    /// "bundle.id=N" pairs, comma separated: windows of that app open on workspace N.
    public var workspaceRules = ""
    /// layout:stack_peek: points each window behind a stack's front one shows of its edge (AeroSpace's accordion padding).
    public var stackPeek = 0.0
    /// `rules:<name>:<field>` entries: windows matched by app name or title (WindowRules.swift).
    public var windowRules: [String: WindowRule] = [:]
    /// Going to the workspace you are on goes back to the one before (AeroSpace's --auto-back-and-forth).
    public var autoBackAndForth = false
    /// Focus and move keys go on into the next workspace at its edge, instead of stopping there.
    public var crossWorkspaces = false

    // animation:*
    public var animationEnabled = true
    public var animationSpeed = 1.0 // 1 flies in 0.8 s
    var animationCurve = CameraCurve.spring

    // navigator:*
    var navigatorEnabled = true
    public var pointer = true

    /// menubar:style. The old menubar:workspaces = false still means the icon.
    public var menuBarStyle = MenuBarStyle.all

    /// notices:workspace: switching workspaces shows their numbers at the bottom of the display for a moment.
    public var workspaceNotice = true

    /// integrations:barik: Barik's menu bar shows mielwm's workspaces (docs/aerospace.md).
    public var barik = false

    /// Chord ("opt+ctrl+g") to action command ("overview").
    public var bindings = Settings.defaultBindings

    public init() {}

    static let defaultBindings: [String: String] = {
        var b: [String: String] = [
            "ctrl+opt+g": "overview",
            "opt+tab": "switch next", "opt+shift+tab": "switch prev",
            "opt+minus": "shrink", "opt+equal": "grow",
            "opt+t": "fill",
            "opt+f": "fullscreen", "opt+o": "pin",
            // AeroSpace's layout keys.
            "opt+slash": "layout tiles", "opt+comma": "layout stack", "opt+period": "layout floating",
            "opt+semicolon": "noop", // AeroSpace's service mode: it must not type … here
            "ctrl+left": "workspace prev", "ctrl+right": "workspace next",
        ]
        for d in Direction.allCases {
            b["opt+\(d.rawValue)"] = "focus \(d.rawValue)"
            b["opt+shift+\(d.rawValue)"] = "nudge \(d.rawValue)"
        }
        for n in 1 ... 9 {
            b["opt+\(n)"] = "workspace \(n)"
            b["opt+shift+\(n)"] = "move-to-workspace \(n)"
        }
        b["opt+0"] = "noop" // beside ⌥1-9, it must not type º
        b["opt+shift+0"] = "noop"
        return b
    }()

    /// The bindings that parse, as the event tap wants them.
    public var chords: [KeyChord: Action] {
        var table: [KeyChord: Action] = [:]
        for (chord, command) in bindings {
            if let c = KeyChord(chord), let a = Action(command: command) { table[c] = a }
        }
        return table
    }

    public var moveModifiers: Modifiers { KeyChord.modifiers(moveModifier) ?? [.control, .option] }

    /// Seconds per camera flight.
    var flightDuration: Double { 0.8 / max(animationSpeed, 0.05) }

    /// `look` with the accent resolved; "auto" takes `systemAccent`.
    public func resolvedLook(systemAccent: RGB? = nil, dark: Bool = true) -> Look {
        var l = look
        l.dark = dark
        l.accent = accentColor(accent) ?? systemAccent ?? .mielOrange
        return l
    }
}

// MARK: - Colors

/// Accent presets, chosen to hold dark or white text. "auto"
/// follows the system accent color.
public let accentPresets: [(name: String, value: String)] = [
    ("Orange", "#ff6b1a"), ("Amber", "#ffb020"), ("Yellow", "#ffe14d"), ("Lime", "#b8f03c"), ("Green", "#3ddc84"),
    ("Mint", "#4dffc3"), ("Teal", "#2ec4b6"), ("Cyan", "#22d3ee"), ("Sky", "#5ab8ff"), ("Blue", "#3b82f6"),
    ("Indigo", "#6366f1"), ("Violet", "#8b5cf6"), ("Purple", "#c084fc"), ("Magenta", "#ff4fd8"), ("Pink", "#ff6fa9"),
    ("Red", "#ff4d4d"), ("White", "#f2f2f2"), ("Auto", "auto"),
]

/// "cyan", "#22d3ee" or "22d3ee" as a color; nil for "auto" and junk.
public func accentColor(_ text: String) -> RGB? {
    let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
    if let preset = accentPresets.first(where: { $0.name.lowercased() == lower }) { return parseHexColor(preset.value) }
    return parseHexColor(lower)
}

public func parseHexColor(_ text: String) -> RGB? {
    var hex = text.trimmingCharacters(in: .whitespaces).lowercased()
    if hex.hasPrefix("#") { hex.removeFirst() } else if hex.hasPrefix("0x") { hex.removeFirst(2) }
    guard hex.count == 6 || hex.count == 8, let v = UInt64(hex.prefix(6), radix: 16) else { return nil }
    return RGB(Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
}

public func hexString(_ c: RGB) -> String {
    func byte(_ v: Double) -> Int { min(255, max(0, Int((v * 255).rounded()))) }
    return String(format: "#%02x%02x%02x", byte(c.r), byte(c.g), byte(c.b))
}
