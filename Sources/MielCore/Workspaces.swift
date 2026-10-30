import CoreGraphics
import Foundation

// AeroSpace's model on the canvas. A workspace is a screen-sized slot in a
// row on the canvas; its members fill it as tiles or as a stack (AeroSpace's
// accordion with no padding), laid out for the screen it was last shown on.
// Floating windows belong to no workspace and live anywhere.

/// Slots 1...9 carry AeroSpace's names; later slots are unnamed.
public struct Workspace: Hashable, Sendable {
    public var slot: Int
    public var mode: LayoutMode // .tiles or .stack
    public var orientation: TileOrientation
    public internal(set) var members: [WindowID] = [] // in tile order
    var weights: [WindowID: Double] = [:] // 1 is an average tile
    var screenID: UInt32? // the screen it was last shown on

    public var number: Int? { slot <= 9 ? slot : nil }
}

/// Where the slots sit: a row on the canvas, `step` apart, that never moves.
public struct SlotGrid: Hashable, Codable, Sendable {
    public var origin: CGPoint // slot 1's top-left
    public var step: CGFloat

    public init(origin: CGPoint, step: CGFloat) {
        self.origin = origin
        self.step = step
    }

    /// Slot 1 where the primary screen is, the rest to the right.
    init(screens: [ScreenInfo], camera: Camera) {
        let primary = primaryScreen(screens)?.frame ?? .zero
        let p = camera.toCanvas(primary.origin, deskCenter: deskCenter(screens))
        origin = CGPoint(x: p.x.rounded(), y: p.y.rounded())
        step = Self.step(for: screens)
    }

    /// Far enough apart that whichever screen a workspace is shown on, its
    /// neighbours stay off every screen, plus a gap. The next one must clear
    /// the whole desk; the one before, shown on the rightmost screen, must
    /// clear the desk's left end, and it can be as wide as the widest screen.
    static func step(for screens: [ScreenInfo]) -> CGFloat {
        let desk = deskRect(screens)
        guard !desk.isNull else { return 240 }
        let reach = screens.map { $0.frame.minX - desk.minX }.max()! + screens.map(\.frame.width).max()!
        return max(desk.width, reach).rounded() + 240
    }

    func origin(_ slot: Int) -> CGPoint { CGPoint(x: origin.x + CGFloat(slot - 1) * step, y: origin.y) }

    /// How far canvas `x` moves to keep its place in its slot when the slots are `step` apart.
    func shift(_ x: CGFloat, toStep step: CGFloat) -> CGFloat {
        max(0, ((x - origin.x) / self.step).rounded(.down)) * (step - self.step)
    }
}

/// The screen with the menu bar (global origin 0,0), else the first.
func primaryScreen(_ screens: [ScreenInfo]) -> ScreenInfo? {
    screens.first { $0.frame.origin == .zero } ?? screens.first
}

/// Tiles for `weights.count` windows in `area`, side by side when
/// `horizontal`, `gap` apart and sized by weight; none under `minLength`
/// while there is room. Edges are whole points and the tiles reach both ends.
func tileFrames(in area: CGRect, weights: [Double], horizontal: Bool, gap: Double,
                minLength: Double = 120) -> [CGRect] {
    let n = weights.count
    guard n > 0 else { return [] }
    let a = area.roundedFrame
    let start = horizontal ? a.minX : a.minY, end = horizontal ? a.maxX : a.maxY
    let available = max(0, end - start - gap * Double(n - 1))
    let w = weights.map { $0.isFinite && $0 > 0 ? $0 : 1 }
    var sizes = w.map { $0 / w.reduce(0, +) * available }
    if minLength * Double(n) <= available {
        // Tiles under the minimum get it; the rest share what is left by weight, until none is under.
        var fixed = Set<Int>()
        while let small = sizes.indices.first(where: { !fixed.contains($0) && sizes[$0] < minLength - 1e-9 }) {
            fixed.insert(small)
            let free = sizes.indices.filter { !fixed.contains($0) }
            let rest = available - minLength * Double(fixed.count), total = free.reduce(0) { $0 + w[$1] }
            for i in sizes.indices { sizes[i] = fixed.contains(i) ? minLength : w[i] / total * rest }
        }
    } else {
        sizes = Array(repeating: available / Double(n), count: n)
    }
    var out: [CGRect] = [], p = start
    for i in 0 ..< n {
        let lo = p.rounded(), hi = i == n - 1 ? end : (p + sizes[i]).rounded()
        out.append(horizontal ? CGRect(x: lo, y: a.minY, width: hi - lo, height: a.height)
            : CGRect(x: a.minX, y: lo, width: a.width, height: hi - lo))
        p += sizes[i] + gap
    }
    return out
}

extension Settings {
    /// What a workspace's tiles fill on `screen`: its visible frame inside the outer gaps.
    func tileArea(on screen: ScreenInfo) -> CGRect {
        let v = screen.visibleFrame, top = screen.isBuiltIn ? gapOuterTop : gapOuterTopExternal
        return CGRect(x: v.minX + gapOuterLeft, y: v.minY + top, width: max(1, v.width - gapOuterLeft - gapOuterRight),
                      height: max(1, v.height - top - gapOuterBottom)).roundedFrame
    }

    func floats(_ bundleID: String?) -> Bool {
        guard let b = bundleID?.lowercased() else { return false }
        return floatingApps.split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == b }
    }

    /// layout:workspace_rules as bundle id (lowercased) to workspace number.
    var workspaceRuleTable: [String: Int] {
        var table: [String: Int] = [:]
        for pair in workspaceRules.split(separator: ",") {
            let parts = pair.split(separator: "=").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, let n = Int(parts[1]), n >= 1 { table[parts[0].lowercased()] = n }
        }
        return table
    }
}

extension CanvasState {
    // MARK: Reading

    func workspaceIndex(_ slot: Int?) -> Int? { slot.flatMap { s in workspaces.firstIndex { $0.slot == s } } }

    func workspace(of id: WindowID) -> Workspace? { workspaceIndex(window(id)?.workspace).map { workspaces[$0] } }

    func layoutScreen(_ ws: Workspace) -> ScreenInfo {
        ws.screenID.flatMap { id in screens.first { $0.id == id } } ?? primaryScreen(screens) ?? activeScreen
    }

    /// A workspace's frame on the canvas: its slot, the size of the screen it lays out for.
    func workspaceFrame(_ slot: Int) -> CGRect {
        let screen = workspaceIndex(slot).map { layoutScreen(workspaces[$0]) } ?? primaryScreen(screens) ?? activeScreen
        return CGRect(origin: slots.origin(slot), size: screen.frame.size)
    }

    /// The slot whose frame holds canvas point `p`, existing or not.
    func slot(under p: CGPoint) -> Int? {
        let k = Int(((p.x - slots.origin.x) / slots.step).rounded(.down)) + 1
        return k >= 1 && workspaceFrame(k).contains(p) ? k : nil
    }

    func isHorizontal(_ ws: Workspace) -> Bool {
        switch ws.orientation {
        case .horizontal: return true
        case .vertical: return false
        case .auto:
            let a = settings.tileArea(on: layoutScreen(ws))
            return a.width >= a.height
        }
    }

    /// Desk to canvas for a workspace on its screen: the screen's top-left is the slot's.
    func canvasRect(_ desk: CGRect, in ws: Workspace) -> CGRect {
        let o = slots.origin(ws.slot), s = layoutScreen(ws).frame.origin
        return desk.offsetBy(dx: o.x - s.x, dy: o.y - s.y)
    }

    /// Canvas tiles of a workspace's shown members (minimized ones and hidden apps take none), in tile order.
    func tiles(_ ws: Workspace) -> [(id: WindowID, frame: CGRect)] {
        let area = settings.tileArea(on: layoutScreen(ws)), horizontal = isHorizontal(ws)
        let shown = ws.members.filter { window($0)?.isShown ?? false }
        let rects = ws.mode == .stack ? Array(repeating: area, count: shown.count)
            : tileFrames(in: area, weights: shown.map { ws.weights[$0] ?? 1 }, horizontal: horizontal,
                         gap: horizontal ? settings.gapInnerHorizontal : settings.gapInnerVertical)
        return zip(shown, rects).map { ($0, canvasRect($1, in: ws)) }
    }

    /// The lowest slot without windows; `skippingRules` keeps the slots rules name for their apps.
    func freeSlot(skippingRules: Bool = false) -> Int {
        let taken = Set(workspaces.filter { !$0.members.isEmpty }.map(\.slot))
            .union(skippingRules ? Set(settings.workspaceRuleTable.values) : [])
        return (1...).first { !taken.contains($0) }!
    }

    /// The slot `camera` rests on: one whose top-left sits on a screen's top-left.
    func restingSlot(_ camera: Camera) -> (slot: Int, screen: ScreenInfo)? {
        guard camera.zoom == 1 else { return nil }
        for s in screens {
            let p = camera.toCanvas(s.frame.origin, deskCenter: deskCenter)
            let k = (p.x - slots.origin.x) / slots.step
            if abs(p.y - slots.origin.y) < 0.5, abs(k - k.rounded()) * slots.step < 0.5, k.rounded() >= 0 {
                return (Int(k.rounded()) + 1, s)
            }
        }
        return nil
    }

    // MARK: Membership

    /// The workspace for `slot`, made if needed (with the mode it had last run while restoring).
    @discardableResult
    mutating func ensureWorkspace(_ slot: Int) -> Int {
        if let k = workspaceIndex(slot) { return k }
        let old = now < restoreUntil ? saved?.workspaces?.first { $0.slot == slot } : nil
        workspaces.append(Workspace(slot: slot, mode: old?.mode ?? (settings.defaultLayout == .stack ? .stack : .tiles),
                                    orientation: old?.orientation ?? settings.orientation))
        workspaces.sort { $0.slot < $1.slot }
        return workspaceIndex(slot)!
    }

    /// Empty workspaces go, except the current one.
    mutating func pruneWorkspaces() {
        workspaces.removeAll { $0.members.isEmpty && $0.slot != currentWorkspace }
    }

    mutating func setCurrent(_ slot: Int) {
        currentWorkspace = slot
        ensureWorkspace(slot)
        pruneWorkspaces()
    }

    /// `id` joins workspace `slot` at `position` (default: the end), leaving
    /// the one it was in. Moving within a workspace keeps its weight.
    mutating func join(_ id: WindowID, _ slot: Int, at position: Int? = nil, weight: Double? = nil) {
        guard let i = index(id) else { return }
        if let pin = windows[i].pinned { // tiling a pinned window puts it back on the canvas first
            windows[i].frame = deskCamera.toCanvas(pin, deskCenter: deskCenter)
            windows[i].pinned = nil
        }
        let old = windows[i].workspace
        if old == nil { windows[i].floatingFrame = windows[i].frame }
        var kept: Double?
        if let k = workspaces.firstIndex(where: { $0.members.contains(id) }) {
            kept = workspaces[k].weights.removeValue(forKey: id)
            workspaces[k].members.removeAll { $0 == id }
        }
        let k = ensureWorkspace(slot)
        workspaces[k].members.insert(id, at: min(max(0, position ?? .max), workspaces[k].members.count))
        workspaces[k].weights[id] = weight ?? (old == slot ? kept : nil) ?? 1
        windows[i].workspace = slot
        fills[id] = nil
        fullscreens[id] = nil
        layoutRevision += 1
        if let old, old != slot { retile(old) }
        retile(slot)
        pruneWorkspaces()
    }

    /// `id` floats: out of its workspace, which tiles again. Works for windows already gone.
    mutating func leave(_ id: WindowID) {
        if let i = index(id) { windows[i].workspace = nil }
        guard let k = workspaces.firstIndex(where: { $0.members.contains(id) }) else { return }
        workspaces[k].members.removeAll { $0 == id }
        workspaces[k].weights[id] = nil
        fills[id] = nil
        fullscreens[id] = nil
        layoutRevision += 1
        retile(workspaces[k].slot)
        pruneWorkspaces()
    }

    /// Members get their tiles (fill and fullscreen win); the real windows follow at 100%.
    mutating func retile(_ slot: Int?) {
        guard let k = workspaceIndex(slot) else { return }
        let ws = workspaces[k], screen = layoutScreen(ws)
        var moved = Set<WindowID>()
        for (id, tile) in tiles(ws) {
            guard let i = index(id) else { continue }
            var f = tile
            if let entry = fullscreens[id], !entry.suspended {
                f = canvasRect(screen.visibleFrame, in: ws)
            } else if fills[id] != nil {
                f = canvasRect(settings.tileArea(on: screen), in: ws)
            }
            guard windows[i].frame != f else { continue }
            windows[i].frame = f
            moved.insert(id)
        }
        guard !moved.isEmpty else { return }
        layoutRevision += 1
        if !isOverview { sync(moved) }
    }

    mutating func retileAll() {
        for ws in workspaces { retile(ws.slot) }
    }

    /// Screens wider than the slots were spaced for (a display came, or the
    /// layout was saved with other ones): the slots move apart. Windows, the
    /// saved layout and the cameras keep their place in their slot.
    mutating func widenSlots() {
        let step = SlotGrid.step(for: screens), old = slots
        guard step > old.step else { return }
        func moved(_ c: Camera) -> Camera {
            let x = restingSlot(c).map { old.origin($0.slot).x } ?? c.center.x
            return Camera(center: CGPoint(x: c.center.x + old.shift(x, toStep: step), y: c.center.y), zoom: c.zoom)
        }
        func moved(_ r: CGRect) -> CGRect { r.offsetBy(dx: old.shift(r.midX, toStep: step), dy: 0) }
        deskCamera = moved(deskCamera)
        returnCamera = returnCamera.map(moved)
        let target = moved(animator.target)
        animator.warp(to: moved(animator.camera), now: now)
        animator.fly(to: target, now: now)
        for i in windows.indices {
            windows[i].frame = moved(windows[i].frame)
            windows[i].floatingFrame = windows[i].floatingFrame.map(moved)
        }
        for k in saved?.windows.indices ?? 0 ..< 0 { saved!.windows[k].frame = moved(saved!.windows[k].frame) }
        slots.step = step
        layoutRevision += 1
        retileAll()
    }

    // MARK: Cameras

    /// The camera that shows workspace `slot` on the active screen at 100%;
    /// its tiles now fit that screen.
    mutating func showWorkspace(_ slot: Int) -> Camera {
        let screen = activeScreen, k = ensureWorkspace(slot)
        if workspaces[k].screenID != screen.id {
            workspaces[k].screenID = screen.id
            retile(slot)
        }
        return roundedAtRest(camera(showing: slots.origin(slot), at: screen.frame.origin, zoom: 1))
    }

    /// Landing on a window: a tiled one brings its whole workspace onto the active screen.
    /// A floating one lives in the workspace it sits in, as in AeroSpace: that
    /// workspace comes on screen and the window moves just enough to be whole,
    /// so it is where it was each time you come back. On a free canvas (new
    /// windows float) the camera goes to the window instead.
    mutating func landingCamera(_ id: WindowID) -> Camera {
        guard let i = index(id) else { return deskCamera }
        let w = windows[i]
        if let slot = w.workspace { return showWorkspace(slot) }
        guard settings.defaultLayout != .floating, w.pinned == nil, let slot = slot(under: w.frame.center) ?? currentWorkspace
        else { return camera(for: w.frame) }
        let camera = showWorkspace(slot), screen = activeScreen
        // The screen's visible frame as it sits in this workspace's slot on the canvas.
        let view = screen.visibleFrame.offsetBy(dx: slots.origin(slot).x - screen.frame.minX, dy: slots.origin(slot).y - screen.frame.minY)
        var f = w.frame
        f.origin.x = min(max(f.minX, view.minX), max(view.minX, view.maxX - f.width))
        f.origin.y = min(max(f.minY, view.minY), max(view.minY, view.maxY - f.height))
        if f.roundedFrame != w.frame {
            windows[i].frame = f.roundedFrame
            layoutRevision += 1
        }
        return camera
    }

    // MARK: New windows

    /// Where a new window goes, nil to float: rules, then (while starting up)
    /// a workspace of its own, else the current workspace after the focused member.
    func placement(for s: WindowSnapshot) -> (slot: Int, position: Int?)? {
        if !s.isResizable || settings.floats(s.bundleID) || settings.defaultLayout == .floating { return nil }
        if let n = s.bundleID.flatMap({ settings.workspaceRuleTable[$0.lowercased()] }) { return (n, nil) }
        // Startup (the restore window): whatever is already open gets its own workspace, so nothing starts as tiny tiles.
        if now < restoreUntil { return (freeSlot(skippingRules: true), nil) }
        guard let c = currentWorkspace, let k = workspaceIndex(c) else { return (freeSlot(), nil) }
        return (c, focused.flatMap { workspaces[k].members.firstIndex(of: $0) }.map { $0 + 1 })
    }

    // MARK: The user moved or resized a tiled window

    /// A resize along the split axis by the user (`resizing`) moves the edge
    /// it shares with the neighbour that way; anything else snaps back to the
    /// tile. An app that keeps refusing gets its way after a couple of tries.
    mutating func userChangedTile(_ i: Int, to frame: CGRect, resizing: Bool = true) {
        let id = windows[i].id
        guard let ws = workspace(of: id) else { return }
        let t = tiles(ws)
        if resizing, ws.mode == .tiles, fills[id] == nil, fullscreens[id] == nil, let p = t.firstIndex(where: { $0.id == id }) {
            let h = isHorizontal(ws), tile = t[p].frame
            let length = h ? frame.width : frame.height, old = h ? tile.width : tile.height
            if abs(length - old) > Self.frameTolerance {
                let movedStart = abs((h ? frame.minX : frame.minY) - (h ? tile.minX : tile.minY)) > Self.frameTolerance
                let q = movedStart ? p - 1 : p + 1
                // Only a resize that still changes the tile once clamped; else an app with a
                // minimum size would get the same frame forever (the capped path below stops it).
                let pair = t.indices.contains(q) ? old + (h ? t[q].frame.width : t[q].frame.height) : 0
                if t.indices.contains(q), abs(min(max(length, 120), pair - 120) - old) > Self.frameTolerance {
                    checkpoint("resize", window: id)
                    setTileLength(id, to: length, neighbour: t[q].id)
                    sync([id], force: true) // the other axis snaps back too
                    return
                }
            }
        }
        // Given in: the tile keeps the size the app insists on. Retiling first would undo that and fight again.
        guard countRepark(i) <= Self.maxReparks else {
            windows[i].frame.size = frame.size
            layoutRevision += 1
            return
        }
        retile(ws.slot) // a gesture may have moved the canvas frame
        sync([id], force: true)
    }

    /// Weights become tile lengths with `id` at `length`; `neighbour` (else
    /// every other tile, by size) makes up the difference. None goes under 120.
    mutating func setTileLength(_ id: WindowID, to length: CGFloat, neighbour: WindowID? = nil) {
        guard let k = workspaces.firstIndex(where: { $0.members.contains(id) }) else { return }
        let ws = workspaces[k], t = tiles(ws), h = isHorizontal(ws), minLength: CGFloat = 120
        guard t.count > 1, let p = t.firstIndex(where: { $0.id == id }) else { return }
        var lengths = t.map { h ? $0.frame.width : $0.frame.height }
        let total = lengths.reduce(0, +)
        if let q = neighbour.flatMap({ n in t.firstIndex { $0.id == n } }) {
            let pair = lengths[p] + lengths[q]
            lengths[p] = min(max(length, minLength), pair - minLength)
            lengths[q] = pair - lengths[p]
        } else {
            let others = total - lengths[p]
            let new = min(max(length, minLength), total - minLength * CGFloat(t.count - 1))
            for j in lengths.indices where j != p { lengths[j] *= (total - new) / max(others, 1) }
            lengths[p] = new
        }
        for (j, tile) in t.enumerated() { workspaces[k].weights[tile.id] = lengths[j] * CGFloat(t.count) / total }
        layoutRevision += 1
        retile(ws.slot)
    }

    // MARK: Dragging a tiled window

    /// Where a dragged tiled window would land: the workspace under its
    /// center, its position there and the tile it would get.
    func dropSpot(_ i: Int) -> (slot: Int, position: Int, tile: CGRect)? {
        let w = windows[i], c = w.frame.center
        guard var ws = workspaces.first(where: { workspaceFrame($0.slot).contains(c) }) else { return nil }
        let weight = workspace(of: w.id)?.weights[w.id] ?? 1
        ws.members.removeAll { $0 == w.id }
        let h = isHorizontal(ws)
        let before = tiles(ws).filter { h ? $0.frame.midX < c.x : $0.frame.midY < c.y }.last
        let position = before.flatMap { b in ws.members.firstIndex(of: b.id) }.map { $0 + 1 } ?? 0
        ws.members.insert(w.id, at: position)
        ws.weights[w.id] = weight
        guard let tile = tiles(ws).first(where: { $0.id == w.id })?.frame else { return nil }
        return (ws.slot, position, tile)
    }
}
