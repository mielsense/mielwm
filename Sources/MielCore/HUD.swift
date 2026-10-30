import CoreGraphics
import Foundation

// The HUDModel the overview's chrome draws, built from the overview machine
// and the canvas: palette rows, footer, hints, help sheet. Text is sentence
// case as written; `{...}` in hints and toasts marks a key drawn as a keycap.

/// The search palette's layout in points (times look.hudScale). The chrome
/// draws with these and the camera aims below them, so the two agree.
public enum PaletteMetrics {
    public static let listInset = 8.0 // above and below the rows, and beside them
    public static let footerHeight = 28.0
    public static let cardGap = 8.0 // between the field and the card of results below it
    public static let helpWidth = 1040.0 // the shortcuts sheet is wider than the field, for three columns
    public static let cardRadius = 20.0 // the card's corners
    public static let rowRadius = cardRadius - listInset // a row's, so the two share a centre

    /// Height of the field (a capsule) and, with `rows` result rows, the card below it.
    /// The camera keeps the canvas clear of this, so both renderers size the card with `cardHeight`.
    public static func height(_ look: Look, rows: Int, footer: Bool) -> Double {
        guard rows > 0 else { return look.searchHeight }
        return look.searchHeight + cardGap + cardHeight(look, rows: rows, footer: footer)
    }

    /// The card of results below the field: its inset, `rows` rows and the "more results" footer.
    public static func cardHeight(_ look: Look, rows: Int, footer: Bool) -> Double {
        listInset * 2 + Double(rows) * look.rowHeight + (footer ? footerHeight : 0)
    }

    /// The ⌥Tab switcher's icons that fit `maxTiles` across: the selected one
    /// (clamped), and the first shown, keeping the selection near the middle.
    public static func switcherWindow(count: Int, selected: Int?, maxTiles: Int) -> (first: Int, shown: Int, selected: Int) {
        let shown = min(count, max(1, maxTiles)), selected = min(max(selected ?? 0, 0), count - 1)
        return (max(0, min(selected - shown / 2, count - shown)), shown, selected)
    }

    /// The palette's top edge, in points from the screen's top; `topInset` is the notch or menu bar.
    public static func top(_ look: Look, screenHeight: Double, topInset: Double) -> Double {
        max(screenHeight * look.paletteTop, topInset + 12 * look.hudScale)
    }

    /// The palette's width in points: the field's, or the shortcuts sheet's with `help`.
    public static func width(_ look: Look, help: Bool = false, screenWidth: Double) -> Double {
        min((help ? max(look.paletteWidth, helpWidth) : look.paletteWidth) * look.hudScale, screenWidth * 0.94)
    }

    /// The search field, the capsule at the top, in points from the screen's top-left.
    public static func fieldFrame(_ look: Look, screenSize: CGSize, topInset: Double) -> CGRect {
        let width = width(look, screenWidth: screenSize.width)
        return CGRect(x: (screenSize.width - width) / 2, y: top(look, screenHeight: screenSize.height, topInset: topInset),
                      width: width, height: look.searchHeight * look.hudScale)
    }

    /// The bottom key-hint pill: its height, and its distance from the screen's bottom (`bottomInset`: the Dock).
    public static func hintsHeight(_ look: Look) -> Double { (look.cornerSize * 2.5 * look.hudScale).rounded() }

    public static func hintsMargin(_ look: Look, bottomInset: Double) -> Double {
        max(20 * look.hudScale, bottomInset + 14 * look.hudScale)
    }
}

/// "{⌃0} Fit all" as [(key ⌃0), (text Fit all)]: the `{...}` spans are keys.
public func hintSegments(_ text: String) -> [(text: String, isKey: Bool)] {
    var out: [(text: String, isKey: Bool)] = []
    var current = "", inKey = false
    for ch in text {
        if ch == "{" || ch == "}" {
            if !current.isEmpty { out.append((current, inKey)) }
            current = ""
            inKey = ch == "{"
        } else {
            current.append(ch)
        }
    }
    if !current.isEmpty { out.append((current, inKey)) }
    return out
}

public extension HelpSection {
    // The shortcuts sheet in points: the title band, a section header, a row, the gap after a section.
    static let titleBand = 52.0, headerHeight = 28.0, lineHeight = 24.0, gap = 14.0

    var height: Double { Self.headerHeight + Double(entries.count) * Self.lineHeight + Self.gap }

    /// Sections split into `count` columns of about equal height, in order.
    static func columns(_ sections: [HelpSection], count: Int) -> [[HelpSection]] {
        let heights = sections.map(\.height)
        let target = heights.reduce(0, +) / Double(max(count, 1))
        var columns: [[HelpSection]] = [[]]
        var acc = 0.0
        for (section, h) in zip(sections, heights) {
            if !columns[columns.count - 1].isEmpty, columns.count < count, acc + h / 2 > target * Double(columns.count) { columns.append([]) }
            columns[columns.count - 1].append(section)
            acc += h
        }
        return columns
    }

    /// A help entry's keys: space-separated keycaps; plain words (Click, drag) as text.
    static func keyTokens(_ keys: String) -> [(text: String, isKey: Bool)] {
        var out: [(text: String, isKey: Bool)] = []
        for token in keys.split(separator: " ").map(String.init) {
            let isKey = token.count == 1 || ["Space", "esc"].contains(token) || token.contains { !$0.isLetter }
            if !isKey, let last = out.last, !last.isKey { out[out.count - 1].text += " " + token } else { out.append((token, isKey)) }
        }
        return out
    }
}

public extension CanvasState {
    /// The HUD for one screen: only the active screen shows the palette.
    func hud(for screen: ScreenInfo) -> HUDModel {
        var h = HUDModel()
        h.toast = toast
        guard settings.navigatorEnabled, overview.isOpen, screen.id == activeScreen.id else { return h }
        let byID = Dictionary(windows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        if overview.switcher && !isOverview {
            guard overview.switcherRevealed(now: now) else { return h }
            h.mode = .switcher
            h.placeholder = "Recent windows"
            h.rows = overview.results.compactMap { r in
                byID[r.id].map { HUDRow(title: $0.displayTitle, detail: $0.appName, bundleID: $0.bundleID) }
            }
            h.selectedRow = h.rows.isEmpty ? nil : overview.selected
            return h
        }
        guard isOverview else { return h }

        h.mode = overview.helpOpen ? .help : .search
        h.query = overview.query
        h.placeholder = "Search windows"
        if overview.listVisible && !overview.helpOpen {
            let view = animator.target.toCanvas(activeScreen.frame.center, deskCenter: deskCenter)
            let rows = max(1, look.paletteRows)
            let end = min(overview.results.count, overview.listOffset + rows)
            h.rows = (overview.listOffset ..< end).compactMap { n in
                let r = overview.results[n]
                guard let w = byID[r.id] else { return nil }
                let hint = directionHint(for: w.frame, viewCenter: view, viewSize: activeScreen.frame.size)
                let row = n - overview.listOffset
                return HUDRow(title: w.displayTitle, detail: hint.isEmpty ? w.appName : w.appName + " · " + hint,
                              bundleID: w.bundleID, trailing: n == overview.selected ? "↩" : row < 9 ? "⌘\(row + 1)" : "",
                              highlights: r.titleRanges)
            }
            h.selectedRow = h.rows.isEmpty ? nil : overview.selected - overview.listOffset
            let more = overview.results.count - end
            if more > 0 { h.footer = "\(more) more \(more == 1 ? "result" : "results"), keep typing or press ↓" }
        }
        h.markedText = overview.markedText
        if overview.helpOpen { h.help = helpSections }
        h.readout = look.cornerLabels ? readout(for: screen) : ""
        h.hints = hints
        return h
    }

    /// The bottom pill: keys and what they do here.
    private var hints: String {
        // Nothing matches: going, next and bringing have nothing to act on.
        if overview.matchSet?.isEmpty == true { return "{esc} Clear the search  {⌘/} Shortcuts" }
        return "{↩} Go  {⇥} Next  {⇧↩} Bring here  {⌘/} Shortcuts  {esc} Back"
    }

    /// The top-right pill: zoom, window count, display.
    private func readout(for screen: ScreenInfo) -> String {
        let total = windows.count { $0.isShown && $0.pinned == nil }
        return "\(Int((camera.zoom * 100).rounded()))%  ·  \(total) \(total == 1 ? "window" : "windows")  ·  \(screen.name)"
    }

    /// Every key, for ⌘/, as (keys, action), most used first. The last two
    /// sections come from the live bindings, so a remap shows. Keys separated
    /// by a space are alternatives; plain words (Click, drag) are not keys.
    var helpSections: [HelpSection] {
        let move = String(KeyChord(modifiers: settings.moveModifiers, key: "a").symbol.dropLast())
        var mouse = [("Click", "Go to a window"), ("Drag", "Move a window"), ("Scroll or drag", "Pan the canvas"),
                     ("Pinch or ⌘ scroll", "Zoom"), (move + " drag", "Move or resize, anywhere"), ("⌃⌥ scroll", "Zoom, anywhere"), ("Middle drag", "Pan, anywhere")]
        if settings.swipeWorkspaces { mouse.insert(("Swipe with three fingers", "Next, previous workspace"), at: 5) }
        if look.minimapEnabled { mouse.append(("Click the minimap", "Jump there")) }
        return [
            HelpSection(title: "Search", entries: [
                ("Type", "Search windows"), ("↑ ↓ ⇥ ⇧⇥", "Next, previous result"), ("↩", "Go to the window"), ("⇧↩", "Bring it here"),
                ("⌘1-9", "Go to that result"), ("esc", "Clear, then go back"),
            ]),
            HelpSection(title: "Mouse and trackpad", entries: mouse),
            HelpSection(title: "Canvas", entries: [
                ("←→↑↓", "Select the nearest window"), ("⇧←→↑↓", "Nudge the selection"), ("⌘←→↑↓", "Pan"), ("⌘= ⌘-", "Zoom in, out"),
                ("⌘0", "Fit every window"), ("⌘F", "Frame the selected window"), ("⌘A", "Tidy windows"), ("⌘Z ⌘⇧Z", "Undo, redo"),
                ("⌘,", "Appearance settings"),
            ]),
            HelpSection(title: "Anywhere", entries: boundEntries(Self.anywhereLabels)
                + (settings.bindings.values.contains("settings") ? [] : [("Menu bar", "Settings…")])),
            HelpSection(title: "Workspaces", entries: boundEntries(Self.layoutLabels)),
        ]
    }

    private static let anywhereLabels: [(String, String)] = [
        ("overview", "Overview, and back"), ("switch", "Recent windows"), ("focus", "Focus that way"),
        ("nudge", "Move the window that way"), ("fill", "Fill the screen"), ("fullscreen", "Fullscreen"), ("pin", "Pin to the screen"),
        ("grow", "Grow, shrink"), ("resize", "Resize"), ("close", "Close the window"), ("minimize", "Minimize"), ("pan", "Pan"), ("zoom", "Zoom"), ("search", "Search"), ("help", "Shortcuts"),
        ("tune", "Appearance settings"), ("fit", "Fit every window"), ("frame", "Frame the selected window"), ("arrange", "Tidy windows"),
        ("undo", "Undo"), ("redo", "Redo"), ("summon", "Bring here"), ("land", "Land"), ("back", "Back"), ("refresh", "Refresh"),
        ("settings", "Settings…"),
    ]

    private static let layoutLabels: [(String, String)] = [
        ("workspace", "Go to workspace"), ("move-to-workspace", "Move the window there"), ("workspace prev", "Previous, next workspace"),
        ("workspace-back-and-forth", "Last workspace, and back again"),
        ("layout tiles", "Tiles, or flip them"), ("layout stack", "Stack"), ("layout floating", "Float, or tile again"),
    ]

    /// Commands listed together under the first one's label.
    private static let helpAliases = ["shrink": "grow", "workspace next": "workspace prev"]

    /// The bound keys for each label's command, in the labels' order. A
    /// numbered command ("workspace 3") counts under its verb.
    private func boundEntries(_ labels: [(String, String)]) -> [(keys: String, action: String)] {
        var byGroup: [String: [KeyChord]] = [:]
        for (chord, command) in settings.bindings {
            guard let c = KeyChord(chord), let action = Action(command: command), action != .noop else { continue }
            let words = action.command.split(separator: " ").map(String.init)
            let group = words.count > 1 && Int(words[1]) == nil && ["layout", "workspace"].contains(words[0]) ? action.command : words[0]
            byGroup[Self.helpAliases[group] ?? group, default: []].append(c)
        }
        let arrows: Set<String> = ["left", "right", "up", "down"]
        let digits = Set((1 ... 9).map(String.init))
        return labels.compactMap { group, label in
            guard let chords = byGroup[group] else { return nil }
            // Four arrows, or the digits 1 to 9, with the same modifiers read as one entry.
            var runs: [Modifiers: [String]] = [:]
            var plain: [String] = []
            for c in chords.sorted(by: { ($0.modifiers.rawValue.nonzeroBitCount, $0.description) < ($1.modifiers.rawValue.nonzeroBitCount, $1.description) }) { // ⌥⇥ before ⌥⇧⇥
                if arrows.contains(c.key) || digits.contains(c.key) { runs[c.modifiers, default: []].append(c.key) } else { plain.append(c.symbol) }
            }
            for (mods, keys) in runs.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                let prefix = String(KeyChord(modifiers: mods, key: "a").symbol.dropLast())
                if Set(keys) == arrows { plain.append(prefix + "←→↑↓") } else if Set(keys) == digits { plain.append(prefix + "1-9") } else {
                    plain.append(keys.map { KeyChord(modifiers: mods, key: $0).symbol }.joined(separator: " "))
                }
            }
            return (plain.joined(separator: " "), label)
        }
    }
}
