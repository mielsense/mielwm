import Foundation

// Port of Navigator.cpp's matcher. Every query word must appear in the title,
// the app name or the app's category name with its letters together and in
// order ("fas" finds FAStfetch, never Free imAgeS); case and accents are
// ignored. Highlights are Character offsets into the displayed title.

/// Coarse app families used by tidy-up, search and labels, by bundle id.
public enum WindowCategory: String, CaseIterable, Sendable {
    case terminal, browser, communication, development, filesNotes, media, other

    public init(bundleID: String?, appName: String, title: String) {
        let app = ((bundleID ?? "") + " " + appName).lowercased()
        let all = app + " " + title.lowercased()
        func any(_ text: String, _ needles: [String]) -> Bool { needles.contains { text.contains($0) } }
        if any(app, ["foot", "alacritty", "kitty", "ghostty", "wezterm", "konsole", "terminal", "iterm", "warp"]) {
            self = .terminal
        } else if any(all, ["slack", "discord", "msteams", "microsoft teams", "signal", "telegram", "whatsapp", "mattermost",
                            "element", "gmail", "mail.google", "outlook", "thunderbird", "hey.com", " imbox", " inbox",
                            "com.apple.mail", "mobilesms", "messages", "zoom.us"]) {
            self = .communication
        } else if any(app, ["chromium", "chrome", "firefox", "brave", "vivaldi", "zen", "browser", "safari", "edgemac", "orion"]) {
            self = .browser
        } else if any(app, ["code", "codium", "jetbrains", "idea", "clion", "pycharm", "webstorm", "zed", "sublime", "emacs",
                            "nvim", "dev", "xcode", "cursor", "nova"]) {
            self = .development
        } else if any(app, ["nautilus", "thunar", "dolphin", "nemo", "files", "obsidian", "notion", "logseq", "notes", "writer",
                            "finder", "forklift", "bear"]) {
            self = .filesNotes
        } else if any(app, ["spotify", "vlc", "mpv", "music", "video", "player", "iina", "quicktime", "podcasts"]) {
            self = .media
        } else {
            self = .other
        }
    }

    /// Searchable words ("term" finds every terminal).
    var searchName: String {
        switch self {
        case .terminal: "terminal"
        case .browser: "browser web"
        case .communication: "chat mail"
        case .development: "code editor"
        case .filesNotes: "files notes"
        case .media: "media music video"
        case .other: "app"
        }
    }

    /// Tidy-up group order.
    var arrangeKey: String {
        switch self {
        case .terminal: "10-terminals"
        case .browser: "20-browsers"
        case .communication: "30-communication"
        case .development: "40-development"
        case .filesNotes: "50-files-notes"
        case .media: "60-media"
        case .other: "90-other"
        }
    }
}

/// One folded character per displayed character, so match positions map
/// straight back onto the text.
struct FoldedText: Sendable {
    var chars: [Character] = []
    var wordStart: [Bool] = []

    init(_ text: String) {
        var previousAlnum = false
        var previous: Character?
        for c in text {
            let alnum = c.isLetter || c.isNumber
            let camel = (previous?.isLowercase ?? false) && c.isUppercase
            chars.append(Self.fold(c))
            wordStart.append(alnum && (!previousAlnum || camel))
            previousAlnum = alnum
            previous = c
        }
    }

    static func fold(_ c: Character) -> Character {
        if let a = c.asciiValue { return (65 ... 90).contains(a) ? Character(UnicodeScalar(a + 32)) : c } // most titles
        return String(c).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).first ?? c
    }
}

/// Typed text a query accepts: no control characters, no leading spaces.
func acceptsTyped(_ text: String, into query: String) -> Bool {
    !text.isEmpty && !(query.isEmpty && text.allSatisfy { $0 == " " })
        && !text.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
}

/// `index` stepped by `delta`, wrapping around `count`.
func wrapped(_ index: Int, _ delta: Int, count: Int) -> Int {
    ((index + delta) % count + count) % count
}

/// A list of `count` rows showing `rows` at once: the selection clamped and
/// the offset scrolled so it shows.
func scrolled(selected: Int, offset: Int, count: Int, rows: Int) -> (selected: Int, offset: Int) {
    let s = count == 0 ? 0 : min(max(selected, 0), count - 1)
    var o = offset
    if s < o { o = s }
    if s >= o + rows { o = s - rows + 1 }
    return (s, min(max(o, 0), max(0, count - rows)))
}

/// Best first; equal scores keep their order.
func stableSortedByScore<T>(_ items: [T], score: (T) -> Int) -> [T] {
    items.enumerated().sorted { (score($0.element), -$0.offset) > (score($1.element), -$1.offset) }.map(\.element)
}

func queryTokens(_ query: String) -> [[Character]] {
    FoldedText(query).chars.split(whereSeparator: \.isWhitespace).map(Array.init)
}

/// Start of the text beats start of a word beats the middle of one; earlier
/// beats later. nil when the token is not in the field.
func scoreToken(_ field: FoldedText, _ token: [Character]) -> (score: Int, start: Int)? {
    let n = field.chars.count, m = token.count
    guard m > 0 else { return (0, 0) }
    guard m <= n else { return nil }
    var best: (score: Int, start: Int)?
    for start in 0 ... (n - m) where field.chars[start ..< start + m].elementsEqual(token) {
        var score = 100 + m * 14 - min(start, 40) / 2
        if start == 0 { score += 70 } else if field.wordStart[start] { score += 45 }
        if score > (best?.score ?? -1) { best = (score, start) }
    }
    return best
}

/// A window the search can find.
public struct SearchCandidate: Hashable, Sendable {
    public var id: WindowID
    public var title: String // as displayed: the app name when the window has no title
    public var appName: String
    public var bundleID: String?

    public init(id: WindowID, title: String, appName: String, bundleID: String? = nil) {
        self.id = id
        self.title = title.isEmpty ? appName : title
        self.appName = appName
        self.bundleID = bundleID
    }
}

/// A window the search found, with its score and the letters that matched.
public struct SearchResult: Hashable, Sendable {
    public var id: WindowID
    var score: Int
    var titleMatches: [Int] // Character offsets into the title
    var appMatches: [Int] // Character offsets into the app name

    /// Matched title characters as contiguous ranges, for HUDRow.highlights.
    var titleRanges: [Range<Int>] {
        var ranges: [Range<Int>] = []
        for i in titleMatches {
            if let last = ranges.last, last.upperBound == i {
                ranges[ranges.count - 1] = last.lowerBound ..< i + 1
            } else {
                ranges.append(i ..< i + 1)
            }
        }
        return ranges
    }
}

/// Ranks `candidates`, which come most recently used first. With no words,
/// every window in that order. `returnWindow` (where the search started)
/// yields slightly, so "term" from a terminal finds the other terminal.
func searchWindows(_ query: String, candidates: [SearchCandidate],
                   returnWindow: WindowID? = nil) -> [SearchResult] {
    let tokens = queryTokens(query)
    var results: [SearchResult] = []
    for (rank, c) in candidates.enumerated() {
        if tokens.isEmpty {
            results.append(SearchResult(id: c.id, score: -rank, titleMatches: [], appMatches: []))
            continue
        }
        let title = FoldedText(c.title), app = FoldedText(c.appName)
        let category = FoldedText(WindowCategory(bundleID: c.bundleID, appName: c.appName, title: c.title).searchName)
        var total = 0
        var titleMatches = Set<Int>(), appMatches = Set<Int>()
        var matched = true
        for token in tokens {
            let t = scoreToken(title, token), a = scoreToken(app, token), k = scoreToken(category, token)
            let best = max(t?.score ?? -1, a.map { $0.score * 85 / 100 } ?? -1, k.map { $0.score * 55 / 100 } ?? -1)
            guard best >= 0 else { matched = false; break }
            total += best
            if let t { titleMatches.formUnion(t.start ..< t.start + token.count) }
            if let a { appMatches.formUnion(a.start ..< a.start + token.count) }
        }
        guard matched else { continue }
        total += max(0, 36 - rank * 4)
        if c.id == returnWindow { total -= 24 }
        results.append(SearchResult(id: c.id, score: total, titleMatches: titleMatches.sorted(),
                                    appMatches: appMatches.sorted()))
    }
    return stableSortedByScore(results, score: \.score) // equal scores keep recency order
}
