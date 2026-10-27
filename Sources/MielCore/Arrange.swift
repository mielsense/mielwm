import CoreGraphics
import Foundation

// Port of Phantomat arrangeCanvasWindows: tidy every window up on the grid,
// grouped by what it is for, with no overlaps.

public struct ArrangeItem: Hashable, Sendable {
    public var id: WindowID
    public var frame: CGRect
    public var category: WindowCategory
    public var tokens: Set<String>

    public init(id: WindowID, frame: CGRect, category: WindowCategory, tokens: Set<String>) {
        self.id = id
        self.frame = frame
        self.category = category
        self.tokens = tokens
    }
}

/// Words that say what a window is for: ASCII words of 4+ letters from its
/// title and app name, minus words that say nothing (pass the user and host
/// names in `extraStopwords`, every terminal title carries them).
public func contextTokens(title: String, appName: String, extraStopwords: Set<String> = []) -> Set<String> {
    let stopwords: Set<String> = [
        "about", "agent", "application", "browser", "chrome", "chromium", "claude", "codex", "default", "desktop",
        "file", "files", "firefox", "foot", "google", "home", "https", "inbox", "manager", "mozilla", "new", "notes",
        "omarchy", "project", "terminal", "untitled", "window", "with",
    ]
    let extra = Set(extraStopwords.map { $0.lowercased() })
    var result = Set<String>()
    let words = (title + " " + appName).lowercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
    for word in words.map(String.init) where word.count >= 4 && !stopwords.contains(word) && !extra.contains(word) {
        result.insert(word)
    }
    return result
}

public struct ArrangeOptions: Hashable, Sendable {
    public var grid: Double = 80
    public var sizeSimilarity: Double = 0.12
    public var resizeLimit: Double = 0.15
    public var contextGrouping = true

    public init(grid: Double = 80, sizeSimilarity: Double = 0.12, resizeLimit: Double = 0.15, contextGrouping: Bool = true) {
        self.grid = grid
        self.sizeSimilarity = sizeSimilarity
        self.resizeLimit = resizeLimit
        self.contextGrouping = contextGrouping
    }
}

/// New canvas frames, packed in rows around `center`, at most `maxRowWidth`
/// wide unless one group is wider. Sizes snap to the grid when that changes
/// them by at most the resize limit; similar windows in one group share a size.
public func arrange(_ items: [ArrangeItem], options o: ArrangeOptions, center: CGPoint,
                    maxRowWidth: Double) -> [WindowID: CGRect] {
    guard !items.isEmpty else { return [:] }
    let grid = max(o.grid, 1)

    // Groups: a shared word across two app categories wins (a project
    // name), else the app category.
    var groupKey = items.map { $0.category.arrangeKey }
    if o.contextGrouping {
        var holders: [String: [Int]] = [:]
        for (i, item) in items.enumerated() {
            for token in item.tokens { holders[token, default: []].append(i) }
        }
        for (i, item) in items.enumerated() {
            var bestToken = "", bestScore = -1
            for token in item.tokens.sorted() {
                guard let members = holders[token], members.count >= 2,
                      Set(members.map { items[$0].category }).count >= 2 else { continue }
                let score = token.count * 100 - members.count
                if score > bestScore { (bestScore, bestToken) = (score, token) }
            }
            if !bestToken.isEmpty { groupKey[i] = "00-context-" + bestToken }
        }
    }

    func relativeChange(_ from: CGSize, _ to: CGSize) -> Double {
        max(abs(to.width - from.width) / max(1, from.width), abs(to.height - from.height) / max(1, from.height))
    }
    func snapped(_ s: CGSize) -> CGSize {
        CGSize(width: max(grid * 2, (s.width / grid).rounded() * grid), height: max(grid * 2, (s.height / grid).rounded() * grid))
    }

    var sizes = items.map(\.frame.size)
    for i in items.indices {
        let candidate = snapped(items[i].frame.size)
        if relativeChange(items[i].frame.size, candidate) <= o.resizeLimit { sizes[i] = candidate }
    }

    var grouped: [String: [Int]] = [:]
    for i in items.indices { grouped[groupKey[i], default: []].append(i) }
    let keys = grouped.keys.sorted()

    for key in keys {
        let indices = grouped[key]!
        var matched = Set<Int>()
        for seed in indices where !matched.contains(seed) {
            var cluster = [seed]
            matched.insert(seed)
            let seedSize = items[seed].frame.size
            for c in indices where !matched.contains(c) {
                let s = items[c].frame.size
                let dw = abs(s.width - seedSize.width) / max(1, s.width, seedSize.width)
                let dh = abs(s.height - seedSize.height) / max(1, s.height, seedSize.height)
                if dw <= o.sizeSimilarity && dh <= o.sizeSimilarity {
                    cluster.append(c)
                    matched.insert(c)
                }
            }
            guard cluster.count >= 2 else { continue }
            let sum = cluster.reduce(CGSize.zero) { CGSize(width: $0.width + items[$1].frame.width, height: $0.height + items[$1].frame.height) }
            let common = snapped(CGSize(width: sum.width / Double(cluster.count), height: sum.height / Double(cluster.count)))
            if cluster.allSatisfy({ relativeChange(items[$0].frame.size, common) <= o.resizeLimit }) {
                for i in cluster { sizes[i] = common }
            }
        }
    }

    // Each group is a small grid of its own.
    struct Group { var indices: [Int]; var local: [CGPoint]; var size: CGSize; var packed = CGPoint.zero }
    var groups: [Group] = []
    for key in keys {
        let indices = grouped[key]!
        let count = indices.count
        let aspect = indices.reduce(0.0) { $0 + sizes[$1].width / max(1, sizes[$1].height) } / Double(count)
        var columns = count <= 1 ? 1 : Int(Double(count).squareRoot().rounded(.up))
        if count <= 3 && aspect >= 1.35 { columns = 1 } // a few landscape windows read better as a column
        let rows = (count + columns - 1) / columns
        var widths = [Double](repeating: 0, count: columns), heights = [Double](repeating: 0, count: rows)
        for (n, i) in indices.enumerated() {
            widths[n % columns] = max(widths[n % columns], sizes[i].width)
            heights[n / columns] = max(heights[n / columns], sizes[i].height)
        }
        var xs = [0.0], ys = [0.0]
        for c in 1 ..< max(columns, 1) { xs.append(xs[c - 1] + widths[c - 1] + grid) }
        for r in 1 ..< max(rows, 1) { ys.append(ys[r - 1] + heights[r - 1] + grid) }
        let local = indices.indices.map { CGPoint(x: xs[$0 % columns], y: ys[$0 / columns]) }
        groups.append(Group(indices: indices, local: local,
                            size: CGSize(width: xs[columns - 1] + widths[columns - 1], height: ys[rows - 1] + heights[rows - 1])))
    }

    let groupGap = grid * 2
    let rowLimit = max(maxRowWidth, groups.map(\.size.width).max() ?? 0)
    var x = 0.0, y = 0.0, rowHeight = 0.0, packedWidth = 0.0
    for g in groups.indices {
        if x > 0 && x + groups[g].size.width > rowLimit {
            x = 0
            y += rowHeight + groupGap
            rowHeight = 0
        }
        groups[g].packed = CGPoint(x: x, y: y)
        x += groups[g].size.width + groupGap
        rowHeight = max(rowHeight, groups[g].size.height)
        packedWidth = max(packedWidth, x - groupGap)
    }
    let packedHeight = y + rowHeight
    let originX = ((center.x - packedWidth / 2) / grid).rounded() * grid
    let originY = ((center.y - packedHeight / 2) / grid).rounded() * grid

    var result: [WindowID: CGRect] = [:]
    for g in groups {
        for (n, i) in g.indices.enumerated() {
            result[items[i].id] = CGRect(origin: CGPoint(x: originX + g.packed.x + g.local[n].x, y: originY + g.packed.y + g.local[n].y),
                                         size: sizes[i])
        }
    }
    return result
}
