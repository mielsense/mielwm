import Foundation

/// What the overview needs to know about the canvas.
public struct OverviewContext: Sendable {
    var candidates: [SearchCandidate] // every window search can find
    var mru: [WindowID] // most recent first
    public var focused: WindowID? // where the session starts
    public var rows: Int // result rows on screen

    public init(candidates: [SearchCandidate], mru: [WindowID], focused: WindowID?, rows: Int) {
        self.candidates = candidates
        self.mru = mru
        self.focused = focused
        self.rows = rows
    }
}

public enum OverviewInput: Hashable, Sendable {
    case key(NamedKey, Modifiers)
    case text(String) // typed text, already through the input method
    case markedText(String) // a dead key waiting for its letter
}

/// What a key asks the canvas to do.
public enum OverviewEffect: Hashable, Sendable {
    case follow(WindowID) // the selection moved: camera and canvas selection follow
    case land(WindowID?) // nil: the canvas selection
    case summon(WindowID?)
    case revert // back to where the session started
    case action(Action)
    case commitSwitcher
    case cancelSwitcher
}

/// The keyboard layer of the zoomed-out canvas (port of Navigator.cpp and
/// navigatorKeyAction): the search palette, the ⌥Tab switcher and the help
/// sheet. Pure: keys in, effects out.
public struct OverviewMachine: Hashable, Sendable {
    static let switcherRevealDelay = 0.17

    private(set) var isOpen = false
    public private(set) var query = ""
    public internal(set) var markedText = ""
    private(set) var listRevealed = false
    public private(set) var selected = 0
    private(set) var listOffset = 0
    private(set) var results: [SearchResult] = []
    public internal(set) var helpOpen = false
    public private(set) var switcher = false // opened by ⌥Tab; releasing ⌥ lands
    private(set) var switcherRevealAt: Double?
    private(set) var returnWindow: WindowID?
    var sessionOrder: [WindowID] = []
    var rows = 6

    public init() {}

    // MARK: - Session

    /// Freezes the recency order for the session, so the list does not
    /// reshuffle while browsing; the window it starts from comes first.
    public mutating func begin(_ ctx: OverviewContext, switcher: Bool = false, now: Double = 0) {
        end()
        isOpen = true
        self.switcher = switcher
        listRevealed = switcher
        switcherRevealAt = switcher ? now + Self.switcherRevealDelay : nil
        returnWindow = ctx.focused
        let ids = ctx.candidates.map(\.id)
        var order = MRU(ctx.mru).sorted(ids)
        if let f = ctx.focused, let i = order.firstIndex(of: f) { order.insert(order.remove(at: i), at: 0) }
        sessionOrder = order
        rebuild(ctx, resetSelection: true)
    }

    public mutating func end() {
        self = OverviewMachine()
    }

    /// The ⌥Tab strip turns into the full overview.
    mutating func leaveSwitcher() {
        switcher = false
        switcherRevealAt = nil
    }

    func switcherRevealed(now: Double) -> Bool {
        switcher && (switcherRevealAt.map { now >= $0 } ?? true)
    }

    // MARK: - Results

    var queryActive: Bool { isOpen && matchSet != nil }
    var listVisible: Bool { isOpen && (queryActive || listRevealed) }

    /// The windows that match while searching, nil with no query (all match).
    private(set) var matchSet: Set<WindowID>?

    var selectedWindow: WindowID? { results.indices.contains(selected) ? results[selected].id : nil }

    /// Re-ranks. Keeps the selected window when it still matches unless
    /// `resetSelection` (a new query always starts at its best hit).
    mutating func rebuild(_ ctx: OverviewContext, resetSelection: Bool) {
        guard isOpen else { return }
        rows = max(1, ctx.rows)
        let previous = resetSelection ? nil : selectedWindow
        let byID = Dictionary(ctx.candidates.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var ordered = sessionOrder.compactMap { byID[$0] }
        let seen = Set(sessionOrder)
        ordered += ctx.candidates.filter { !seen.contains($0.id) } // opened during the session
        results = searchWindows(query, candidates: ordered, returnWindow: returnWindow)
        matchSet = queryTokens(query).isEmpty ? nil : Set(results.map(\.id))
        selected = previous.flatMap { p in results.firstIndex { $0.id == p } } ?? 0
        if resetSelection { listOffset = 0 }
        keepVisible()
    }

    mutating func keepVisible() {
        (selected, listOffset) = scrolled(selected: selected, offset: listOffset, count: results.count, rows: rows)
    }

    mutating func selectWindow(_ id: WindowID) {
        guard let i = results.firstIndex(where: { $0.id == id }) else { return }
        selected = i
        keepVisible()
    }

    mutating func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selected = wrapped(selected, delta, count: results.count)
        listRevealed = true
        keepVisible()
    }

    mutating func setQuery(_ text: String, _ ctx: OverviewContext) -> [OverviewEffect] {
        query = text
        markedText = ""
        return edited(true, ctx)
    }

    // MARK: - Keys

    public mutating func handle(_ input: OverviewInput, _ ctx: OverviewContext) -> [OverviewEffect] {
        guard isOpen else { return [] }
        switch input {
        case let .markedText(text):
            markedText = text
            return []
        case let .text(text):
            markedText = ""
            if switcher { return [] }
            // Leading spaces carry no meaning and would only hide the placeholder.
            guard acceptsTyped(text, into: query) else { return [] }
            query += text
            return edited(true, ctx)
        case let .key(key, mods):
            return handleKey(key, mods, ctx)
        }
    }

    private mutating func edited(_ changed: Bool, _ ctx: OverviewContext) -> [OverviewEffect] {
        guard changed else { return [] }
        // Clearing the query keeps whatever is selected; a real query jumps to its best hit.
        let searching = !queryTokens(query).isEmpty
        rebuild(ctx, resetSelection: searching)
        return searching ? selectedWindow.map { [.follow($0)] } ?? [] : []
    }

    private mutating func moved(_ delta: Int) -> [OverviewEffect] {
        moveSelection(delta)
        return selectedWindow.map { [.follow($0)] } ?? []
    }

    private mutating func popChar() -> Bool {
        guard !query.isEmpty else { return false }
        query.removeLast()
        return true
    }

    private mutating func popWord() -> Bool {
        guard !query.isEmpty else { return false }
        while query.last == " " { query.removeLast() }
        while let last = query.last, last != " " { query.removeLast() }
        return true
    }

    private mutating func handleKey(_ key: NamedKey, _ mods: Modifiers, _ ctx: OverviewContext) -> [OverviewEffect] {
        let ctrl = mods.contains(.control), shift = mods.contains(.shift)
        let opt = mods.contains(.option), cmd = mods.contains(.command)

        if switcher { // only Esc means anything while the strip is up
            return key == .escape && !ctrl ? [.cancelSwitcher] : []
        }
        // ⌘ the Mac way; ⌃ still accepted, as older versions had it.
        let command = (cmd || ctrl) && !opt
        if command && key == .character(",") { return [.action(.tune)] } // the usual settings chord: Appearance
        // ⌘/ (⌘?) is the Mac's Help shortcut; F1 needs fn on most Mac keyboards, so it is only a spare.
        if key == .f1 || (command && (key == .character("/") || key == .character("?"))) {
            helpOpen.toggle()
            return []
        }

        if case let .arrow(direction) = key {
            if cmd { return [.action(.pan(direction))] } // ⌘ arrows: pan, where Mission Control takes ⌃ arrows
            if shift && !ctrl { return [.action(.nudge(direction))] }
            if ctrl && !shift { return [.action(.pan(direction))] }
            if ctrl || shift || opt { return [] }
            if listVisible && (direction == .up || direction == .down) { return moved(direction == .up ? -1 : 1) }
            return [.action(.focus(direction))]
        }

        switch key {
        case .escape:
            if command { return [] }
            if helpOpen { helpOpen = false; return [] }
            if !query.isEmpty { query = ""; markedText = ""; return edited(true, ctx) }
            if listRevealed { listRevealed = false; return [] }
            return [.revert]
        case .enter:
            if command { return [] }
            if queryActive && results.isEmpty { return [] }
            let window = (!queryActive && !listRevealed) ? nil : selectedWindow
            return [shift ? .summon(window) : .land(window)]
        case .tab:
            return command ? [] : moved(shift ? -1 : 1)
        case .backspace:
            if cmd { // ⌘⌫ clears the field, as in every Mac text field
                let had = !query.isEmpty
                query = ""
                return edited(had, ctx)
            }
            return edited(ctrl || opt ? popWord() : popChar(), ctx)
        default:
            break
        }

        guard command else { return [] }
        switch key {
        case .equals: return [.action(.zoomIn)]
        case .minus: return [.action(.zoomOut)]
        case .digit(0): return [.action(.fit)]
        case let .digit(n) where (1 ... 9).contains(n):
            let index = listOffset + n - 1
            return results.indices.contains(index) ? [.land(results[index].id)] : []
        case let .character(c):
            switch (c.lowercased(), ctrl) {
            // Readline keys, ⌃ only as in every Mac text field.
            case ("u", true): query = ""; return edited(true, ctx)
            case ("w", true): return edited(popWord(), ctx)
            case ("n", true), ("j", true): return moved(1)
            case ("p", true), ("k", true): return moved(-1)
            case ("a", _): return [.action(.arrange)]
            case ("z", _): return [.action(shift ? .redo : .undo)]
            case ("y", true): return [.action(.redo)]
            case ("f", _): return [.action(.frame)]
            case ("+", _): return [.action(.zoomIn)] // ⌘+ on layouts where = needs no shift
            default: return []
            }
        default:
            return []
        }
    }
}
