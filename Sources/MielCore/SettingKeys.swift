import Foundation

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

/// config.json's setting names and what each one sets, with its range.
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
    "layout:stack_peek": .number(\.stackPeek, 0 ... 16),
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
    "notices:workspace": .flag(\.workspaceNotice),
    "integrations:barik": .flag(\.barik),
]

public extension Settings {
    /// Every setting name config.json accepts, besides `keys:<chord>`.
    static var keys: [String] {
        (Array(settingPaths.keys) + ["canvas:grid_style", "animation:curve", "navigator:search_border_color",
                                     "layout:default", "layout:orientation", "appearance:glass"]).sorted()
    }

    /// What config.json holds for `key` to give `value`: nil (no entry) when it is the default.
    static func entry(_ key: String, _ value: SettingValue) -> SettingValue? {
        var s = Settings()
        guard s.set(value, forKey: key) == nil, s.value(forKey: key) != Settings().value(forKey: key) else { return nil }
        return value
    }

    func value(forKey key: String) -> SettingValue? {
        switch key {
        case "canvas:grid_style": return .text(look.gridDots ? "dots" : "lines")
        case "animation:curve": return .text(animationCurve.rawValue)
        case "layout:default": return .text(defaultLayout.rawValue)
        case "layout:orientation": return .text(orientation.rawValue)
        case "appearance:glass": return .text(look.glass.rawValue)
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
        case "appearance:glass":
            guard case let .text(t) = value, let style = GlassStyle(rawValue: t.lowercased()) else {
                return "'\(key)' takes \"liquid\" or \"frosted\""
            }
            look.glass = style
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
extension SettingValue {
    var json: Any {
        switch self {
        case let .number(n): n
        case let .flag(b): b
        case let .text(s): s
        }
    }
}
