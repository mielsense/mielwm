import CoreGraphics
import Foundation

/// Everything the user can set. `look` is what Render reads; the rest is
/// behaviour. Defaults match Phantomat's except where macOS needs its own.
public struct Settings: Hashable, Codable, Sendable {
    public var look = Look()
    /// navigator:accent: a preset name, #rrggbb, or "auto" for the system accent.
    public var accent = "auto"

    // canvas:*
    public var initialZoom = 0.72
    public var minZoom = 0.05
    public var maxZoom = 2.5
    public var zoomStep = 0.12 // wheel zoom strength
    public var autoPlace = true
    public var placementGap = 40.0
    public var snapEnabled = true // snaps to look.gridSize
    public var rememberLayout = true
    public var arrangeContextGrouping = true
    public var arrangeSizeSimilarity = 0.12
    public var arrangeResizeLimit = 0.15
    public var gap = 12.0 // Fill keeps this far from the screen edges (Phantomat gaps_out)

    // input:*
    public var panSensitivity = 1.0
    public var dragThreshold = 10.0
    public var scrollFactor = 1.0
    public var moveModifier = "ctrl+opt" // held with a left/right drag to move/resize a window
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
    public var gapOuterTopExternal = 54.0 // other displays (room for a status bar)
    /// Bundle ids that always float, comma separated.
    public var floatingApps = "com.apple.systempreferences,com.apple.ActivityMonitor,com.apple.calculator,com.apple.archiveutility"
    /// "bundle.id=N" pairs, comma separated: windows of that app open on workspace N.
    public var workspaceRules = ""

    // animation:*
    public var animationEnabled = true
    public var animationSpeed = 1.0 // 1 flies in 0.8 s
    public var animationCurve = CameraCurve.spring

    // navigator:*
    public var navigatorEnabled = true
    public var pointer = true

    /// menubar:workspaces: the menu bar shows the workspace numbers instead of the icon.
    public var menuBarWorkspaces = true

    /// Chord ("opt+ctrl+g") to action command ("overview").
    public var bindings = Settings.defaultBindings

    public init() {}

    public static let defaultBindings: [String: String] = {
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
    public var flightDuration: Double { 0.8 / max(animationSpeed, 0.05) }

    /// `look` with the accent resolved; "auto" takes `systemAccent`.
    public func resolvedLook(systemAccent: RGB? = nil, dark: Bool = true) -> Look {
        var l = look
        l.dark = dark
        l.accent = accentColor(accent) ?? systemAccent ?? .mielOrange
        return l
    }
}

// MARK: - Colors

/// Accent presets from Phantomat, chosen to hold dark or white text. "auto"
/// follows the system accent color.
public let accentPresets: [(name: String, value: String)] = [
    ("Orange", "#ff6b1a"), ("Amber", "#ffb020"), ("Yellow", "#ffe14d"), ("Lime", "#b8f03c"), ("Green", "#3ddc84"),
    ("Mint", "#4dffc3"), ("Teal", "#2ec4b6"), ("Cyan", "#22d3ee"), ("Sky", "#5ab8ff"), ("Blue", "#3b82f6"),
    ("Indigo", "#6366f1"), ("Violet", "#8b5cf6"), ("Purple", "#c084fc"), ("Magenta", "#ff4fd8"), ("Pink", "#ff6fa9"),
    ("Red", "#ff4d4d"), ("White", "#f2f2f2"), ("Auto", "auto"),
]

/// The preset `accent` names, by name or by value.
func accentPresetIndex(_ accent: String) -> Int? {
    let lower = accent.lowercased()
    return accentPresets.firstIndex { $0.name.lowercased() == lower || $0.value == lower }
}

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

// MARK: - Settings by key (config.json)

/// One setting's value as JSON carries it.
public enum SettingValue: Hashable, Codable, Sendable {
    case number(Double), flag(Bool), text(String)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .flag(b) } else if let n = try? c.decode(Double.self) { self = .number(n) } else { self = .text(try c.decode(String.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case let .number(n): try c.encode(n)
        case let .flag(b): try c.encode(b)
        case let .text(s): try c.encode(s)
        }
    }

    var number: Double? {
        switch self {
        case let .number(n): n
        case let .flag(b): b ? 1 : 0
        case .text: nil
        }
    }
}

enum SettingPath: @unchecked Sendable { // key paths are immutable values
    case number(WritableKeyPath<Settings, Double>, ClosedRange<Double>)
    case integer(WritableKeyPath<Settings, Int>, ClosedRange<Double>)
    case flag(WritableKeyPath<Settings, Bool>)
    case text(WritableKeyPath<Settings, String>)
}

/// Phantomat's setting names (below plugin:spatialoverview:), where the port has them.
let settingPaths: [String: SettingPath] = [
    "distortion:enabled": .flag(\.look.lensEnabled),
    "distortion:strength": .number(\.look.lensStrength, -0.5 ... 0.5),
    "distortion:edge_scale": .number(\.look.lensEdgeScale, 1 ... 1.5),
    "distortion:feather": .number(\.look.lensFeather, 0 ... 0.25),
    "distortion:transition_power": .number(\.look.lensTransitionPower, 0.1 ... 8),
    "distortion:edge_blur": .number(\.look.edgeBlur, 0 ... 1),
    "distortion:edge_blur_start": .number(\.look.edgeBlurStart, 0 ... 0.95),
    "distortion:vignette": .number(\.look.vignette, 0 ... 1),
    "distortion:chromatic": .number(\.look.chromatic, 0 ... 1),
    "canvas:background_dim": .number(\.look.backgroundDim, 0 ... 0.9),
    "canvas:grid_enabled": .flag(\.look.gridEnabled),
    "canvas:grid_size": .number(\.look.gridSize, 24 ... 400),
    "canvas:grid_width": .number(\.look.gridWidth, 1 ... 8),
    "canvas:grid_opacity": .number(\.look.gridOpacity, 0 ... 0.5),
    "canvas:grid_dot_size": .number(\.look.gridDotSize, 2 ... 16),
    "canvas:initial_zoom": .number(\.initialZoom, 0.05 ... 0.95),
    "canvas:min_zoom": .number(\.minZoom, 0.01 ... 1),
    "canvas:max_zoom": .number(\.maxZoom, 1 ... 10),
    "canvas:zoom_step": .number(\.zoomStep, 0.01 ... 1),
    "canvas:auto_place": .flag(\.autoPlace),
    "canvas:placement_gap": .number(\.placementGap, 0 ... 400),
    "canvas:snap_enabled": .flag(\.snapEnabled),
    "canvas:remember_layout": .flag(\.rememberLayout),
    "canvas:arrange_context_grouping": .flag(\.arrangeContextGrouping),
    "canvas:arrange_size_similarity": .number(\.arrangeSizeSimilarity, 0 ... 0.5),
    "canvas:arrange_resize_limit": .number(\.arrangeResizeLimit, 0 ... 0.5),
    "canvas:minimap_enabled": .flag(\.look.minimapEnabled),
    "canvas:minimap_width": .number(\.look.minimapWidth, 80 ... 800),
    "canvas:minimap_height": .number(\.look.minimapHeight, 60 ... 600),
    "canvas:minimap_margin": .number(\.look.minimapMargin, 0 ... 200),
    "canvas:minimap_opacity": .number(\.look.minimapOpacity, 0 ... 1),
    "canvas:gap": .number(\.gap, 0 ... 200),
    "wallpaper": .flag(\.look.wallpaperEnabled),
    "blur": .flag(\.look.blur),
    "blur_strength": .number(\.look.blurStrength, 0 ... 1),
    "parallax:enabled": .flag(\.look.parallaxEnabled),
    "parallax:strength": .number(\.look.parallaxStrength, 0 ... 0.5),
    "parallax:depth": .number(\.look.parallaxDepth, 0 ... 1),
    "input:pan_sensitivity": .number(\.panSensitivity, 0.05 ... 5),
    "input:drag_threshold": .number(\.dragThreshold, 0 ... 100),
    "input:scroll_factor": .number(\.scrollFactor, 0.05 ... 10),
    "input:move_modifier": .text(\.moveModifier),
    "input:swipe_workspaces": .flag(\.swipeWorkspaces),
    "gaps:inner_horizontal": .number(\.gapInnerHorizontal, 0 ... 200),
    "gaps:inner_vertical": .number(\.gapInnerVertical, 0 ... 200),
    "gaps:outer_left": .number(\.gapOuterLeft, 0 ... 400),
    "gaps:outer_right": .number(\.gapOuterRight, 0 ... 400),
    "gaps:outer_bottom": .number(\.gapOuterBottom, 0 ... 400),
    "gaps:outer_top": .number(\.gapOuterTop, 0 ... 400),
    "gaps:outer_top_external": .number(\.gapOuterTopExternal, 0 ... 400),
    "layout:floating_apps": .text(\.floatingApps),
    "layout:workspace_rules": .text(\.workspaceRules),
    "animation:enabled": .flag(\.animationEnabled),
    "animation:speed": .number(\.animationSpeed, 0.2 ... 8),
    "navigator:enabled": .flag(\.navigatorEnabled),
    "navigator:labels": .flag(\.look.labels),
    "navigator:dim_unmatched": .number(\.look.dimUnmatched, 0 ... 1),
    "navigator:pointer": .flag(\.pointer),
    "navigator:accent": .text(\.accent),
    "navigator:mono_font": .text(\.look.monoFont),
    "navigator:hud_scale": .number(\.look.hudScale, 0.5 ... 2),
    "navigator:width": .number(\.look.paletteWidth, 360 ... 1400),
    "navigator:top": .number(\.look.paletteTop, 0 ... 0.5),
    "navigator:rows": .integer(\.look.paletteRows, 3 ... 12),
    "navigator:row_height": .number(\.look.rowHeight, 36 ... 96),
    "navigator:rounding": .number(\.look.rounding, 0 ... 30),
    "navigator:panel_opacity": .number(\.look.panelOpacity, 0 ... 1),
    "navigator:uppercase": .flag(\.look.uppercase),
    "navigator:letter_spacing": .number(\.look.letterSpacing, 0 ... 3),
    "navigator:query_size": .number(\.look.querySize, 10 ... 32),
    "navigator:title_size": .number(\.look.titleSize, 9 ... 26),
    "navigator:detail_size": .number(\.look.detailSize, 7 ... 20),
    "navigator:corner_size": .number(\.look.cornerSize, 8 ... 22),
    "navigator:label_size": .number(\.look.labelSize, 7 ... 20),
    "navigator:corner_labels": .flag(\.look.cornerLabels),
    "navigator:search_height": .number(\.look.searchHeight, 36 ... 110),
    "navigator:search_border": .number(\.look.searchBorder, 0 ... 6),
    "navigator:search_border_opacity": .number(\.look.searchBorderOpacity, 0 ... 1),
    "navigator:search_glow": .number(\.look.searchGlow, 0 ... 1),
    "window:rounding": .number(\.look.windowRounding, 0 ... 40),
    "window:shadow": .flag(\.look.windowShadow),
    "menubar:workspaces": .flag(\.menuBarWorkspaces),
]

public extension Settings {
    /// Every setting name config.json accepts, besides `keys:<chord>`.
    static var keys: [String] {
        (Array(settingPaths.keys) + ["canvas:grid_style", "animation:curve", "navigator:search_border_color",
                                     "layout:default", "layout:orientation"]).sorted()
    }

    func value(forKey key: String) -> SettingValue? {
        switch key {
        case "canvas:grid_style": return .text(look.gridDots ? "dots" : "lines")
        case "animation:curve": return .text(animationCurve.rawValue)
        case "layout:default": return .text(defaultLayout.rawValue)
        case "layout:orientation": return .text(orientation.rawValue)
        case "navigator:search_border_color": return .text(look.searchBorderColor.map(hexString) ?? "accent")
        default: break
        }
        switch settingPaths[key] {
        case let .number(path, _): return .number(self[keyPath: path])
        case let .integer(path, _): return .number(Double(self[keyPath: path]))
        case let .flag(path): return .flag(self[keyPath: path])
        case let .text(path): return .text(self[keyPath: path])
        case nil: return nil
        }
    }

    /// Sets one setting, clamped to its range. Returns an error message
    /// instead when the key is unknown or the value has the wrong type.
    @discardableResult
    mutating func set(_ value: SettingValue, forKey key: String) -> String? {
        let wrongType = "'\(key)' has the wrong type"
        switch key {
        case "canvas:grid_style":
            switch value {
            case let .text(s) where ["dots", "lines"].contains(s.lowercased()): look.gridDots = s.lowercased() == "dots"
            case let .number(n): look.gridDots = n >= 0.5
            default: return "'\(key)' takes \"dots\" or \"lines\""
            }
            return nil
        case "animation:curve":
            guard case let .text(s) = value, let curve = CameraCurve(rawValue: s.lowercased()) else {
                return "'\(key)' takes \"spring\" or \"bezier\""
            }
            animationCurve = curve
            return nil
        case "layout:default":
            guard case let .text(t) = value, let mode = LayoutMode(rawValue: t.lowercased()) else {
                return "'\(key)' takes \"tiles\", \"stack\" or \"floating\""
            }
            defaultLayout = mode
            return nil
        case "layout:orientation":
            guard case let .text(t) = value, let o = TileOrientation(rawValue: t.lowercased()) else {
                return "'\(key)' takes \"auto\", \"horizontal\" or \"vertical\""
            }
            orientation = o
            return nil
        case "navigator:search_border_color":
            guard case let .text(s) = value else { return wrongType }
            if s.lowercased() == "accent" { look.searchBorderColor = nil; return nil }
            guard let c = accentColor(s) else { return "'\(key)' takes \"accent\", a preset or #rrggbb" }
            look.searchBorderColor = c
            return nil
        default: break
        }
        guard let path = settingPaths[key] else { return "unknown setting '\(key)'" }
        switch (path, value) {
        case let (.number(p, range), v):
            guard let n = v.number, n.isFinite else { return wrongType }
            self[keyPath: p] = min(max(n, range.lowerBound), range.upperBound)
        case let (.integer(p, range), v):
            guard let n = v.number, n.isFinite else { return wrongType }
            self[keyPath: p] = Int(min(max(n, range.lowerBound), range.upperBound).rounded())
        case let (.flag(p), .flag(b)): self[keyPath: p] = b
        case let (.flag(p), .number(n)): self[keyPath: p] = n >= 0.5
        case let (.text(p), .text(s)):
            if key == "navigator:accent", s.lowercased() != "auto", accentColor(s) == nil {
                return "'\(key)' takes a preset name, #rrggbb or auto"
            }
            if key == "input:move_modifier", KeyChord.modifiers(s) == nil { return "'\(key)' takes modifiers like \"ctrl+opt\"" }
            self[keyPath: p] = s
        default: return wrongType
        }
        return nil
    }
}

// MARK: - Files

public struct ConfigPaths: Hashable, Sendable {
    public var config: URL

    public init(config: URL) {
        self.config = config
    }

    /// ~/.config/mielwm/config.json. `MIELWM_CONFIG_DIR` moves it (tests run beside the real config).
    public static func standard(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> ConfigPaths {
        let dir = ProcessInfo.processInfo.environment["MIELWM_CONFIG_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? home.appendingPathComponent(".config/mielwm", isDirectory: true)
        return ConfigPaths(config: dir.appendingPathComponent("config.json"))
    }
}

public struct LoadedSettings: Hashable, Sendable {
    public var settings: Settings
    public var errors: [String] // one line each, for the menu bar and the log
}

/// Reads config.json. A missing file is fine; a file that is not JSON is
/// skipped whole with an error; a bad key costs only that key.
public func loadSettings(_ paths: ConfigPaths) -> LoadedSettings {
    parseSettings(config: try? Data(contentsOf: paths.config), configName: paths.config.lastPathComponent)
}

public func parseSettings(config: Data?, configName: String = "config.json") -> LoadedSettings {
    var result = LoadedSettings(settings: Settings(), errors: [])
    func apply(_ data: Data?, name: String) {
        guard let data, !data.isEmpty else { return }
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data, options: [.json5Allowed]) } catch {
            result.errors.append("\(name): not valid JSON, using defaults (\(jsonErrorDetail(error)))")
            return
        }
        guard let dict = object as? [String: Any] else {
            result.errors.append("\(name): expected an object at the top")
            return
        }
        for (key, raw) in flatten(dict) {
            if key.hasPrefix("keys:") {
                let chord = String(key.dropFirst(5))
                guard let command = raw as? String else { result.errors.append("\(name): binding '\(chord)' needs an action string"); continue }
                guard let parsed = KeyChord(chord) else { result.errors.append("\(name): cannot read the keys '\(chord)'"); continue }
                // The same chord may be spelled differently in the defaults.
                for existing in result.settings.bindings.keys where KeyChord(existing) == parsed {
                    result.settings.bindings[existing] = nil
                }
                if command.isEmpty || command == "none" { continue }
                guard Action(command: command) != nil else { result.errors.append("\(name): unknown action '\(command)' for '\(chord)'"); continue }
                result.settings.bindings[parsed.description] = command
                continue
            }
            guard let value = settingValue(raw) else { result.errors.append("\(name): '\(key)' has an unsupported value"); continue }
            if let error = result.settings.set(value, forKey: key) { result.errors.append("\(name): \(error)") }
        }
    }
    apply(config, name: configName)
    return result
}

/// {"distortion": {"strength": 0.2}} and {"distortion:strength": 0.2} mean the same.
private func flatten(_ dict: [String: Any], prefix: String = "") -> [(String, Any)] {
    dict.sorted { $0.key < $1.key }.flatMap { key, value -> [(String, Any)] in
        let full = prefix.isEmpty ? key : prefix + ":" + key
        if let nested = value as? [String: Any] { return flatten(nested, prefix: full) }
        return [(full, value)]
    }
}

private func settingValue(_ raw: Any) -> SettingValue? {
    if let n = raw as? NSNumber {
        return CFGetTypeID(n) == CFBooleanGetTypeID() ? .flag(n.boolValue) : .number(n.doubleValue)
    }
    return (raw as? String).map(SettingValue.text)
}

private func jsonErrorDetail(_ error: Error) -> String {
    (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? error.localizedDescription
}

// MARK: - Editing config.json (the Settings window)

public struct ConfigWriteError: Error, CustomStringConvertible {
    public var description: String
}

/// Sets setting keys and `keys:<chord>` bindings in config.json (nil
/// removes one), keeping everything else, flat or nested. Never overwrites
/// a config.json that is not valid JSON.
public func updateConfig(_ changes: [String: SettingValue?], paths: ConfigPaths) throws {
    guard !changes.isEmpty else { return }
    var config = try readObject(paths.config)
    for (key, value) in changes {
        removeKey(key, from: &config)
        if let value { config[canonicalKey(key)] = value.json }
    }
    try writeObject(config, to: paths.config)
}

private func readObject(_ url: URL) throws -> [String: Any] {
    guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [:] }
    let object: Any
    do { object = try JSONSerialization.jsonObject(with: data, options: [.json5Allowed]) } catch {
        throw ConfigWriteError(description: "\(url.lastPathComponent) is not valid JSON (\(jsonErrorDetail(error))). Fix it first.")
    }
    guard let dict = object as? [String: Any] else {
        throw ConfigWriteError(description: "\(url.lastPathComponent) does not hold an object at the top. Fix it first.")
    }
    return dict
}

private func writeObject(_ dict: [String: Any], to url: URL) throws {
    var data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    data.append(0x0A)
    let target = url.resolvingSymlinksInPath() // a dotfiles symlink stays a symlink
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: target, options: .atomic)
}

/// Removes `key` wherever it sits (flat or nested); a binding also under
/// any other spelling of its chord. Nested objects left empty go too.
private func removeKey(_ key: String, from dict: inout [String: Any], prefix: String = "") {
    let chord = key.hasPrefix("keys:") ? KeyChord(String(key.dropFirst(5))) : nil
    for (k, value) in dict {
        let full = prefix.isEmpty ? k : prefix + ":" + k
        if var nested = value as? [String: Any] {
            removeKey(key, from: &nested, prefix: full)
            dict[k] = nested.isEmpty ? nil : nested
        } else if full == key || (chord != nil && full.hasPrefix("keys:") && KeyChord(String(full.dropFirst(5))) == chord) {
            dict[k] = nil
        }
    }
}

private func canonicalKey(_ key: String) -> String {
    guard key.hasPrefix("keys:"), let chord = KeyChord(String(key.dropFirst(5))) else { return key }
    return "keys:" + chord.description
}

extension SettingValue {
    var json: Any {
        switch self {
        case let .number(n): n
        case let .flag(b): b
        case let .text(s): s
        }
    }
}

public extension Settings {
    /// What config.json holds for `key` to give `value`: nil (no entry) when it is the default.
    static func entry(_ key: String, _ value: SettingValue) -> SettingValue? {
        var s = Settings()
        guard s.set(value, forKey: key) == nil, s.value(forKey: key) != Settings().value(forKey: key) else { return nil }
        return value
    }

    /// What config.json holds for `chord` to do `command` (nil: nothing):
    /// nil (no entry) when that is the default, "none" to unbind a default.
    static func bindingEntry(_ chord: KeyChord, _ command: String?) -> SettingValue? {
        let standard = defaultBindings.first { KeyChord($0.key) == chord }?.value
        if standard.flatMap(Action.init(command:)) == command.flatMap(Action.init(command:)) { return nil }
        return .text(command ?? "none")
    }

    /// The modifiers of the chords that open the overview, when there are
    /// two or more of them: holding them warms the window captures, as the
    /// key is about to follow. One alone (⌥ for ⌥Space) is held for too
    /// many other things to start every capture each time.
    var warmModifiers: Set<Modifiers> {
        Set(chords.compactMap { chord, action in
            switch action {
            case .toggleOverview, .search, .help: chord.modifiers.rawValue.nonzeroBitCount >= 2 ? chord.modifiers : nil
            default: nil
            }
        })
    }

    /// The chords bound to `action`, in a stable order.
    func chords(for action: Action) -> [KeyChord] {
        chords.filter { $0.value == action }.map(\.key).sorted { $0.description < $1.description }
    }

    /// The config edits that move `action` from chord `old` to `new`
    /// (nil `old` adds a chord, nil `new` removes one).
    func rebind(_ action: Action, from old: KeyChord?, to new: KeyChord?) -> [String: SettingValue?] {
        var changes: [String: SettingValue?] = [:]
        if let old, old != new { changes["keys:\(old)"] = Settings.bindingEntry(old, nil) }
        if let new { changes["keys:\(new)"] = Settings.bindingEntry(new, action.command) }
        return changes
    }

    /// The config edits that give `action` (every action, for nil) its default chords back.
    func restoreDefaults(for action: Action?) -> [String: SettingValue?] {
        let standard = Settings()
        let affected = action.map { standard.chords(for: $0) + chords(for: $0) } ?? Array(standard.chords.keys) + Array(chords.keys)
        return Dictionary(affected.map { ("keys:\($0)", SettingValue?.none) }, uniquingKeysWith: { a, _ in a })
    }
}

/// Actions bound one per digit or arrow key under the same modifiers, which
/// the Settings window edits as one shortcut ("⌥1–9").
public enum ShortcutFamily: CaseIterable, Sendable {
    case workspace, moveToWorkspace, focus, nudge

    /// Each action with the key it goes on.
    public var members: [(action: Action, key: String)] {
        switch self {
        case .workspace: (1 ... 9).map { (.workspace($0), "\($0)") }
        case .moveToWorkspace: (1 ... 9).map { (.moveToWorkspace($0), "\($0)") }
        case .focus: Direction.allCases.map { (.focus($0), $0.rawValue) }
        case .nudge: Direction.allCases.map { (.nudge($0), $0.rawValue) }
        }
    }

    public var usesDigits: Bool { self == .workspace || self == .moveToWorkspace }

    public func contains(_ action: Action) -> Bool { members.contains { $0.action == action } }
}

/// How a family is bound: not at all, every member on its key under the same modifiers, or anything else.
public enum FamilyBinding: Hashable, Sendable {
    case none, modifiers(Modifiers), custom
}

public extension Settings {
    func binding(of family: ShortcutFamily) -> FamilyBinding {
        let bound = family.members.map { chords(for: $0.action) }
        if bound.allSatisfy(\.isEmpty) { return .none }
        guard let m = bound.first?.first?.modifiers else { return .custom }
        let uniform = zip(family.members, bound).allSatisfy { $1 == [KeyChord(modifiers: m, key: $0.key)] }
        return uniform ? .modifiers(m) : .custom
    }

    /// The config edits that put every member of `family` on its key under
    /// `modifiers`, dropping the chords it had (nil: no shortcuts at all).
    func rebind(_ family: ShortcutFamily, to modifiers: Modifiers?) -> [String: SettingValue?] {
        var changes: [String: SettingValue?] = [:]
        for member in family.members {
            for old in chords(for: member.action) { changes["keys:\(old)"] = Settings.bindingEntry(old, nil) }
        }
        for member in family.members {
            guard let modifiers else { break }
            let chord = KeyChord(modifiers: modifiers, key: member.key)
            changes["keys:\(chord)"] = Settings.bindingEntry(chord, member.action.command)
        }
        return changes
    }

    /// The config edits that give every member of `family` its default chords back.
    func restoreDefaults(for family: ShortcutFamily) -> [String: SettingValue?] {
        family.members.reduce(into: [:]) { changes, member in changes.merge(restoreDefaults(for: member.action)) { a, _ in a } }
    }

    /// The actions (not no-ops, not `mine`) already on `new` chords.
    func conflicts(_ new: [KeyChord], except mine: (Action) -> Bool) -> [(chord: KeyChord, action: Action)] {
        new.compactMap { c in chords[c].flatMap { $0 == .noop || mine($0) ? nil : (c, $0) } }
    }
}

public extension KeyChord {
    /// Every key name a chord can use.
    static var allKeys: Set<String> { keyNames }
}

/// Pretty JSON, written atomically, directories made as needed.
func writeJSON(_ value: some Encodable, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(value).write(to: url, options: .atomic)
}

// MARK: - Key chords and action names

/// A key with modifiers, written "ctrl+opt+g" in the config.
public struct KeyChord: Hashable, Codable, Sendable, CustomStringConvertible {
    public var modifiers: Modifiers
    /// Lowercase key name: a...z, 0...9, f1...f12, tab, space, return, escape,
    /// delete, forwarddelete, left, right, up, down, minus, equal, comma,
    /// period, slash, semicolon, quote, grave, backslash, leftbracket,
    /// rightbracket, home, end, pageup, pagedown.
    public var key: String

    public init(modifiers: Modifiers, key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    static let keyNames: Set<String> = {
        var names: Set<String> = ["tab", "space", "return", "escape", "delete", "forwarddelete", "left", "right", "up", "down",
                                  "minus", "equal", "comma", "period", "slash", "semicolon", "quote", "grave", "backslash",
                                  "leftbracket", "rightbracket", "home", "end", "pageup", "pagedown"]
        names.formUnion("abcdefghijklmnopqrstuvwxyz0123456789".map(String.init))
        names.formUnion((1 ... 12).map { "f\($0)" })
        return names
    }()

    static let aliases: [String: String] = [
        "-": "minus", "=": "equal", ",": "comma", ".": "period", "/": "slash", ";": "semicolon", "'": "quote",
        "`": "grave", "\\": "backslash", "[": "leftbracket", "]": "rightbracket", "esc": "escape", "enter": "return",
        "backspace": "delete", "←": "left", "→": "right", "↑": "up", "↓": "down",
    ]

    /// "opt", "option", "alt", "⌥"; "ctrl", "control", "⌃"; "cmd", "command", "⌘"; "shift", "⇧".
    static func modifier(_ word: String) -> Modifiers? {
        switch word {
        case "opt", "option", "alt", "⌥": .option
        case "ctrl", "control", "⌃": .control
        case "cmd", "command", "⌘": .command
        case "shift", "⇧": .shift
        default: nil
        }
    }

    /// "ctrl+opt" as modifiers, nil if any word is not one.
    public static func modifiers(_ text: String) -> Modifiers? {
        var m: Modifiers = []
        for word in text.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            guard let one = modifier(word) else { return nil }
            m.insert(one)
        }
        return m.isEmpty ? nil : m
    }

    public init?(_ text: String) {
        var parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.popLast(), !last.isEmpty else { return nil }
        var m: Modifiers = []
        for word in parts {
            guard let one = Self.modifier(word) else { return nil }
            m.insert(one)
        }
        let key = Self.aliases[last] ?? last
        guard Self.keyNames.contains(key) else { return nil }
        self.init(modifiers: m, key: key)
    }

    public var description: String {
        let names: [(Modifiers, String)] = [(.control, "ctrl"), (.option, "opt"), (.shift, "shift"), (.command, "cmd")]
        return (names.filter { modifiers.contains($0.0) }.map(\.1) + [key]).joined(separator: "+")
    }

    /// "⌃⌥G", as the help sheet shows it.
    public var symbol: String {
        let names: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let keySymbols = ["left": "←", "right": "→", "up": "↑", "down": "↓", "tab": "⇥", "return": "↩", "escape": "⎋",
                          "delete": "⌫", "minus": "-", "equal": "=", "comma": ",", "period": ".", "slash": "/",
                          "semicolon": ";", "space": "Space"]
        return names.filter { modifiers.contains($0.0) }.map(\.1).joined() + (keySymbols[key] ?? key.uppercased())
    }
}

public extension Action {
    /// `mielwm <command>` and binding names: "overview", "search [text]",
    /// "tune", "help", "switch next|prev", "focus|nudge|pan left|right|up|down",
    /// "zoom in|out", "fit", "frame", "summon", "land", "back", "fill",
    /// "fullscreen", "pin", "grow", "shrink", "arrange", "undo", "redo",
    /// "refresh", "noop".
    init?(command: String) {
        let words = command.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1).map(String.init)
        guard let verb = words.first?.lowercased() else { return nil }
        let rest = words.count > 1 ? words[1].trimmingCharacters(in: .whitespaces) : ""
        let direction = Direction(rawValue: rest.lowercased())
        switch (verb, rest.lowercased()) {
        case ("overview", ""): self = .toggleOverview
        case ("search", _): self = .search(rest.isEmpty ? nil : rest)
        case ("tune", ""): self = .tune
        case ("help", ""): self = .help
        case ("switch", "next"): self = .switchWindow(forward: true)
        case ("switch", "prev"): self = .switchWindow(forward: false)
        case ("focus", _) where direction != nil: self = .focus(direction!)
        case ("nudge", _) where direction != nil: self = .nudge(direction!)
        case ("pan", _) where direction != nil: self = .pan(direction!)
        case ("zoom", "in"): self = .zoomIn
        case ("zoom", "out"): self = .zoomOut
        case ("fit", ""): self = .fit
        case ("frame", ""): self = .frame
        case ("summon", ""): self = .summon
        case ("land", ""): self = .land
        case ("back", ""): self = .back
        case ("fill", ""): self = .fill
        case ("fullscreen", ""): self = .fullscreen
        case ("pin", ""): self = .pin
        case ("grow", ""): self = .grow
        case ("shrink", ""): self = .shrink
        case ("arrange", ""): self = .arrange
        case ("undo", ""): self = .undo
        case ("redo", ""): self = .redo
        case ("refresh", ""): self = .refresh
        case ("noop", ""): self = .noop
        case ("layout", "tiles"), ("layout", "tiling"): self = .layoutTiles
        case ("layout", "stack"), ("layout", "accordion"): self = .layoutStack
        case ("layout", "floating"): self = .toggleFloating
        case ("workspace", "next"): self = .workspaceStep(forward: true)
        case ("workspace", "prev"): self = .workspaceStep(forward: false)
        case ("workspace", _) where Int(rest).map({ (1 ... 9).contains($0) }) == true: self = .workspace(Int(rest)!)
        case ("move-to-workspace", _), ("move-node-to-workspace", _):
            guard let n = Int(rest), (1 ... 9).contains(n) else { return nil }
            self = .moveToWorkspace(n)
        case ("settings", ""): self = .settings
        default: return nil
        }
    }

    var command: String {
        switch self {
        case .toggleOverview: "overview"
        case let .search(text): text.map { "search \($0)" } ?? "search"
        case .tune: "tune"
        case .help: "help"
        case let .switchWindow(forward): forward ? "switch next" : "switch prev"
        case let .focus(d): "focus \(d.rawValue)"
        case let .nudge(d): "nudge \(d.rawValue)"
        case let .pan(d): "pan \(d.rawValue)"
        case .zoomIn: "zoom in"
        case .zoomOut: "zoom out"
        case .fit: "fit"
        case .frame: "frame"
        case .summon: "summon"
        case .land: "land"
        case .back: "back"
        case .fill: "fill"
        case .fullscreen: "fullscreen"
        case .pin: "pin"
        case .grow: "grow"
        case .shrink: "shrink"
        case .arrange: "arrange"
        case .undo: "undo"
        case .redo: "redo"
        case .refresh: "refresh"
        case .noop: "noop"
        case .layoutTiles: "layout tiles"
        case .layoutStack: "layout stack"
        case .toggleFloating: "layout floating"
        case let .workspace(n): "workspace \(n)"
        case let .workspaceStep(forward): forward ? "workspace next" : "workspace prev"
        case let .moveToWorkspace(n): "move-to-workspace \(n)"
        case .settings: "settings"
        }
    }
}
