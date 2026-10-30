import CoreGraphics
import Foundation

// What each Action and overview key does to the canvas.

extension CanvasState {
    /// The window an action means: the overview's selection, else the focused one.
    var target: Int? { index(isOverview ? (selection ?? focused) : focused) }

    mutating func perform(_ action: Action) {
        switch action {
        case .toggleOverview: isOverview ? closeOverview() : openOverview()
        case let .search(text):
            openOverview()
            if let text { applyOverview(overview.setQuery(text, overviewContext)) }
        case .tune: // the Settings window's Appearance pane (the app opens it), above an overview that steps aside
            back()
            appearanceRequests += 1
        case .help:
            openOverview()
            overview.helpOpen = true
        case let .switchWindow(forward): switchWindow(forward: forward)
        case let .focus(d): focus(d)
        case let .nudge(d): nudge(d)
        case let .pan(d): pan(d)
        case .zoomIn, .zoomOut:
            if !isOverview { openOverview() }
            let factor: CGFloat = action == .zoomIn ? 1.25 : 0.8
            fly(to: zoomed(animator.target, at: freeAreaCenter, to: animator.target.zoom * factor))
        case .fit: fitAll()
        case .frame: frameTarget()
        case .summon: if isOverview { summon(nil) }
        case .land: if isOverview { closeOverview() }
        case .back: back()
        case .fill: toggleFill()
        case .fullscreen: toggleFullscreen()
        case .pin: togglePin()
        case .grow: resizeTarget(look.gridSize, tile: 50)
        case .shrink: resizeTarget(-look.gridSize, tile: -50)
        case let .resize(axis, amount): resizeTarget(CGFloat(amount), tile: CGFloat(amount), axis: axis)
        case .arrange: arrangeAll()
        case .undo: showToast(undo(redo: false) ? "Undone  {⌃⇧Z} Redo" : "Nothing to undo")
        case .redo: showToast(undo(redo: true) ? "Redone" : "Nothing to redo")
        case .refresh: sync(force: true)
        case .noop: break
        case .layoutTiles: setLayout(.tiles)
        case .layoutStack: setLayout(.stack)
        case .toggleFloating: toggleFloating()
        case let .workspace(n): goToWorkspace(n)
        case .workspaceBackAndForth: if let p = previousWorkspace { goToWorkspace(p) }
        case let .workspaceStep(forward): stepWorkspace(forward: forward)
        case let .moveToWorkspace(n): moveToWorkspace(n)
        case .settings: break // the app opens the Settings window
        }
    }

    /// What a bound key does. With layout:auto_back_and_forth the key of the
    /// workspace you are on goes to the one before; the command line and
    /// Barik stay put, as AeroSpace's `workspace N` without the flag does.
    public func boundAction(_ action: Action) -> Action {
        guard settings.autoBackAndForth, case let .workspace(n) = action, n == currentWorkspace, let p = previousWorkspace else { return action }
        return .workspace(p)
    }

    // MARK: Overview

    mutating func openOverview(zoom: CGFloat? = nil, at point: CGPoint? = nil) {
        guard !isOverview else { return }
        // ⌃⌥G over a fullscreen window takes the screen back: it is on the canvas where it was, windowed.
        if let f = focused, let i = index(f), let entry = fullscreens[f], !entry.suspended {
            fullscreens[f]?.suspended = true
            if let slot = windows[i].workspace { retile(slot) } else { windows[i].frame = entry.before }
        }
        isOverview = true
        isPanning = false
        returnCamera = deskCamera
        selection = focused.flatMap { f in candidates.contains { $0.id == f } ? f : nil } ?? mru.sorted(candidates.map(\.id)).first
        if overview.isOpen { overview.leaveSwitcher() } else { overview.begin(overviewContext, now: now) }
        if let s = selection { overview.selectWindow(s) }
        let to = point.map { zoomed(animator.target, at: $0, to: zoom ?? settings.initialZoom) } ?? overviewOpeningCamera
        openedCamera = to
        fly(to: to, transition: 1)
    }

    /// Back to 100% at `camera`. By default: where the session started if
    /// the camera has not moved, else the workspace in the middle of the
    /// free area, else whatever is there, zoomed in around it.
    mutating func closeOverview(to camera: Camera? = nil) {
        guard isOverview else { return }
        let middle = animator.target.toCanvas(freeAreaCenter, deskCenter: deskCenter)
        let unmoved = openedCamera == animator.target
        isOverview = false
        overview.end()
        selection = nil
        dragging = nil
        dropIndicator = nil
        openedCamera = nil
        if let camera { return settle(at: camera) }
        if unmoved, let back = returnCamera { return settle(at: back) }
        if let slot = slot(under: middle), workspaceIndex(slot) != nil { return settle(at: showWorkspace(slot)) }
        settle(at: self.camera(showing: middle, at: activeScreen.frame.center, zoom: 1))
    }

    /// Esc at the end: back to where the session started; nothing else moves.
    mutating func back() {
        guard isOverview else { return }
        if let f = focused, fullscreens[f]?.suspended == true, let i = index(f) { refullscreen(i) }
        closeOverview(to: returnCamera)
    }

    /// Landing on a window brings it in front, at 100%, focused.
    mutating func landOn(_ id: WindowID?) {
        guard let id = id ?? selection ?? focused, let i = index(id), windows[i].isShown else { return closeOverview() }
        raise(i)
        let cam = landingCamera(id)
        for (other, entry) in fullscreens where other != id && entry.suspended { fullscreens[other] = nil } // picking another leaves it windowed
        if isOverview { closeOverview(to: cam) } else { cut(to: cam) }
        if fullscreens[id]?.suspended == true, let j = index(id) { refullscreen(j) }
        focusWindow(id)
    }

    mutating func refullscreen(_ i: Int) {
        let id = windows[i].id
        let screen = screenShowingMost(deskFrame(windows[i]), of: screens) ?? activeScreen
        windows[i].frame = deskCamera.toCanvas(screen.visibleFrame, deskCenter: deskCenter)
        fullscreens[id]?.suspended = false
        sync([id])
    }

    mutating func focusWindow(_ id: WindowID) {
        focused = id
        mru.note(id)
        expectedFocus = (id, now + 0.6)
        outbox.append(.focus(id))
    }

    /// The selection moved in the overview. The camera stays while the
    /// window shows whole in the free area; otherwise it glides, never
    /// zooming, to the window's workspace (when that fits) or to the window
    /// (one too big for the area shows its top, where its title bar is).
    mutating func follow(_ id: WindowID) {
        guard isOverview, let w = window(id) else { return }
        selection = id
        guard w.pinned == nil else { return } // pinned windows sit on the screen, always in view
        let screen = activeScreen, area = overviewFreeArea(on: screen), zoom = animator.target.zoom
        func shows(_ r: CGRect, _ c: Camera) -> Bool { area.insetBy(dx: -0.5, dy: -0.5).contains(lensedBounds(r, camera: c, on: screen)) }
        if shows(w.frame, animator.target) { return }
        if let slot = w.workspace {
            let c = camera(framingWorkspace: slot, maxZoom: zoom)
            if abs(c.zoom - zoom) < 1e-6 { return fly(to: c) }
        }
        let c = camera(fitting: w.frame, in: framingArea, maxZoom: zoom)
        if abs(c.zoom - zoom) < 1e-6 { return fly(to: c) }
        fly(to: camera(showing: CGPoint(x: w.frame.midX, y: w.frame.minY), atScreenPoint: CGPoint(x: area.midX, y: area.minY),
                       on: screen, zoom: zoom))
    }

    /// The desk point at the middle of the overview's free area, through the lens.
    var freeAreaCenter: CGPoint {
        let screen = activeScreen
        let p = lensSourcePoint(overviewFreeArea(on: screen).center, screenSize: screen.frame.size, look: look, transition: 1)
        return CGPoint(x: p.x + screen.frame.minX, y: p.y + screen.frame.minY)
    }

    /// ⇧Enter: the window comes to the middle of the view the session
    /// started from, and the camera goes back there to meet it.
    mutating func summon(_ id: WindowID?) {
        guard let id = id ?? selection ?? focused, let i = index(id), windows[i].pinned == nil else { return }
        checkpoint("summon", window: id)
        let origin = returnCamera ?? deskCamera
        if windows[i].workspace != nil { // a tiled window joins the workspace the session started from
            if let slot = restingSlot(origin)?.slot ?? currentWorkspace { join(id, slot) }
            if let j = index(id) { raise(j) }
            if isOverview { closeOverview(to: origin) } else { settle(at: origin) }
            return focusWindow(id)
        }
        let p = origin.toCanvas(activeScreen.visibleFrame.center, deskCenter: deskCenter)
        var f = windows[i].frame.centered(at: p)
        if settings.snapEnabled { f = snapToGrid(f, grid: look.gridSize) }
        windows[i].frame = f.roundedFrame
        raise(i)
        if isOverview { closeOverview(to: origin) } else { settle(at: origin) }
        focusWindow(id)
    }

    /// ⌘0: every window (every match while searching) in view.
    mutating func fitAll() {
        let matches = overview.matchSet
        let frames = candidates.filter { matches?.contains($0.id) ?? true }.map(\.frame)
        guard let first = frames.first else { return }
        let bounds = frames.reduce(first) { $0.union($1) }
        guard bounds.width > 0, bounds.height > 0 else { return }
        if !isOverview { openOverview() }
        fly(to: camera(fitting: bounds, maxZoom: 0.9), transition: 1)
    }

    /// ⌘F: the selected window fills the free area, up to 100% (beyond that it would only blur).
    mutating func frameTarget() {
        guard let i = target, windows[i].pinned == nil else { return }
        if !isOverview { openOverview() }
        let w = windows[i]
        selection = w.id
        overview.selectWindow(w.id)
        fly(to: camera(fitting: w.frame, in: framingArea, maxZoom: 1))
    }

    mutating func pan(_ d: Direction) {
        let v = d.vector, s = activeScreen.frame.size, c = animator.target
        let moved = Camera(center: CGPoint(x: c.center.x + v.dx * s.width * 0.22 / c.zoom, y: c.center.y + v.dy * s.height * 0.22 / c.zoom), zoom: c.zoom)
        if isOverview { fly(to: moved) } else { settle(at: moved) }
    }

    /// One grid step; the camera follows only once the window starts to leave the view.
    mutating func nudge(_ d: Direction) {
        guard let i = target, windows[i].pinned == nil else { return }
        let id = windows[i].id
        if windows[i].workspace != nil { return nudgeTile(id, d) }
        checkpoint("nudge", window: id)
        let step = max(8, look.gridSize), v = d.vector
        windows[i].frame = windows[i].frame.offsetBy(dx: v.dx * step, dy: v.dy * step)
        fills[id] = nil
        layoutRevision += 1
        let c = isOverview ? animator.target : deskCamera
        let view = c.toCanvas(activeScreen.frame, deskCenter: deskCenter).insetBy(dx: step, dy: step)
        let chased = Camera(center: CGPoint(x: c.center.x + v.dx * step, y: c.center.y + v.dy * step), zoom: c.zoom)
        if isOverview {
            if !view.contains(windows[i].frame.center) { fly(to: chased) }
        } else if !view.contains(windows[i].frame.center) {
            settle(at: chased)
        } else {
            sync([id])
        }
    }

    /// Arrows: the nearest window that way. Zoomed out the selection moves
    /// and the camera follows; at 100% it gets focus and the camera moves
    /// only if it is not fully on screen.
    mutating func focus(_ d: Direction) {
        // In a stack the arrows along it cycle its windows; past the ends they go on as usual.
        if !isOverview, let i = target, let ws = workspace(of: windows[i].id), ws.mode == .stack, d.isHorizontal == isHorizontal(ws) {
            let shown = tiles(ws).map(\.id)
            if let p = shown.firstIndex(of: windows[i].id), shown.indices.contains(p + d.sign) { return reveal(shown[p + d.sign]) }
        }
        let from = target.map { windows[$0] }
        let matches = isOverview ? overview.matchSet : nil
        var pool = candidates.filter { $0.id != from?.id && (matches?.contains($0.id) ?? true) }
        if staysInWorkspace { // AeroSpace stops at the workspace's edge; the overview roams the canvas
            let home = from.flatMap(homeSlot) ?? currentWorkspace
            pool = pool.filter { [nil, home].contains(homeSlot($0)) } // nil: pinned, or off every slot (another display)
        }
        guard let id = nearestWindow(from: from?.frame, direction: d, candidates: pool.map { ($0.id, $0.frame) }) else { return }
        if isOverview {
            follow(id)
            overview.selectWindow(id)
            return
        }
        reveal(id)
    }

    /// Focus and move keys stop at the workspace's edge: at 100%, with workspaces, unless set to cross.
    var staysInWorkspace: Bool { !isOverview && !settings.crossWorkspaces && settings.defaultLayout != .floating }

    /// At 100%: focus it, and move the camera only if it is not fully on screen.
    mutating func reveal(_ id: WindowID) {
        guard let i = index(id) else { return }
        raise(i)
        focusWindow(id)
        if let w = window(id), w.pinned == nil, !isFullyVisible(w) { cut(to: landingCamera(id)) }
    }

    // MARK: Window keys

    /// Fill (⌥T): the screen it is on minus menu bar and Dock, with the gap;
    /// again puts it back (see restoredFrame). From the overview it lands first.
    mutating func toggleFill() {
        guard let i = target, windows[i].pinned == nil, windows[i].isResizable else { return }
        let id = windows[i].id
        if isOverview { landOn(id) }
        guard let j = index(id) else { return }
        if let slot = windows[j].workspace { // tiled: the whole tile area, in front; again back to its tile
            fills[id] = fills[id] == nil ? RestoreEntry(before: windows[j].frame, filled: windows[j].frame) : nil
            raise(j)
            return retile(slot)
        }
        if let entry = fills[id], let back = restoredFrame(current: windows[j].frame, entry: entry) {
            windows[j].frame = back
            fills[id] = nil
        } else {
            let screen = screenShowingMost(deskFrame(windows[j]), of: screens) ?? activeScreen
            let filled = deskCamera.toCanvas(fillArea(on: screen, gap: settings.gap), deskCenter: deskCenter).roundedFrame
            fills[id] = RestoreEntry(before: windows[j].frame, filled: filled)
            windows[j].frame = filled
        }
        raise(j)
        layoutRevision += 1
        sync([id])
    }

    /// Fullscreen on its own screen (⌥F): the screen's visible frame, no gap
    /// (macOS keeps the menu bar). Again puts it back.
    mutating func toggleFullscreen() {
        guard let i = target, windows[i].pinned == nil, windows[i].isResizable else { return }
        let id = windows[i].id
        if isOverview { landOn(id) }
        guard let j = index(id) else { return }
        if let slot = windows[j].workspace { // tiled: the visible frame, no gaps; again back to its tile
            if fullscreens[id]?.suspended == true { return refullscreen(j) }
            fullscreens[id] = fullscreens[id] == nil ? FullscreenEntry(before: windows[j].frame) : nil
            raise(j)
            return retile(slot)
        }
        if let entry = fullscreens[id] {
            if entry.suspended { return refullscreen(j) }
            windows[j].frame = entry.before
            fullscreens[id] = nil
        } else {
            let screen = screenShowingMost(deskFrame(windows[j]), of: screens) ?? activeScreen
            fullscreens[id] = FullscreenEntry(before: windows[j].frame)
            windows[j].frame = deskCamera.toCanvas(screen.visibleFrame, deskCenter: deskCenter).roundedFrame
        }
        raise(j)
        layoutRevision += 1
        sync([id])
    }

    /// Pin (⌥O): stays put on the screen while the canvas moves; again puts
    /// it back on the canvas where it then is.
    mutating func togglePin() {
        guard let i = target, fullscreens[windows[i].id] == nil else { return }
        let id = windows[i].id
        if isOverview { landOn(id) }
        guard let j = index(id) else { return }
        if windows[j].workspace != nil { leave(id) } // a tiled window floats first
        if let pin = windows[j].pinned {
            windows[j].frame = deskCamera.toCanvas(pin, deskCenter: deskCenter)
            windows[j].pinned = nil
        } else {
            windows[j].pinned = desiredFrame(windows[j]).frame
        }
        layoutRevision += 1
        sync([id])
    }

    /// ⌥= / ⌥- and AeroSpace's resize: a floating window `step` bigger or
    /// smaller around its center (`axis`: both sides, or one), a tile `tile`
    /// points along the split. Flat tiles can't change across the split.
    mutating func resizeTarget(_ step: CGFloat, tile change: CGFloat, axis: ResizeAxis = .smart) {
        guard let i = target, windows[i].isResizable else { return }
        let id = windows[i].id
        if let ws = workspace(of: id) {
            let h = isHorizontal(ws)
            guard ws.mode == .tiles, axis == .smart || (axis == .width) == h,
                  let tile = tiles(ws).first(where: { $0.id == id })?.frame else { return }
            checkpoint("resize", window: id)
            return setTileLength(id, to: (h ? tile.width : tile.height) + change)
        }
        checkpoint("resize", window: id)
        let dw = axis == .height ? 0 : step, dh = axis == .width ? 0 : step
        if let pin = windows[i].pinned {
            windows[i].pinned = pin.resized(width: dw, height: dh).roundedFrame
        } else {
            windows[i].frame = windows[i].frame.resized(width: dw, height: dh).roundedFrame
        }
        fills[id] = nil
        layoutRevision += 1
        if !isOverview { sync([id]) }
    }

    /// ⌘A: every window tidied up on the grid, grouped by what it is for.
    mutating func arrangeAll() {
        let items = candidates.filter { $0.workspace == nil }.map { // tiled windows keep their tiles
            ArrangeItem(id: $0.id, frame: $0.frame, category: WindowCategory(bundleID: $0.bundleID, appName: $0.appName, title: $0.title),
                        tokens: contextTokens(title: $0.title, appName: $0.appName, extraStopwords: stopwords))
        }
        guard !items.isEmpty else { return }
        checkpoint("arrange")
        let center = (isOverview ? animator.target : deskCamera).toCanvas(activeScreen.frame.center, deskCenter: deskCenter)
        let options = ArrangeOptions(grid: look.gridSize, sizeSimilarity: settings.arrangeSizeSimilarity,
                                     resizeLimit: settings.arrangeResizeLimit, contextGrouping: settings.arrangeContextGrouping)
        let frames = arrange(items, options: options, center: center, maxRowWidth: activeScreen.frame.width * 1.9)
        for i in windows.indices {
            guard let f = frames[windows[i].id] else { continue }
            windows[i].frame = f
            fills[windows[i].id] = nil
            fullscreens[windows[i].id] = nil
        }
        showToast("Tidied \(items.count) windows  {⌘Z} Undo")
        layoutRevision += 1
        if !isOverview { sync() }
    }

    // MARK: Layouts and workspaces

    /// ⌥/ and ⌥, (AeroSpace's layout tiles and accordion). A floating window
    /// joins the workspace under it, else the current one (⌥, makes that a
    /// stack). A tiled one switches its workspace: stack and tiles swap, ⌥/
    /// in tiles flips the orientation.
    mutating func setLayout(_ mode: LayoutMode) {
        guard let i = target else { return }
        let id = windows[i].id
        checkpoint("layout", window: id)
        guard let ws = workspace(of: id), let k = workspaceIndex(ws.slot) else {
            let to = (windows[i].pinned == nil ? slot(under: windows[i].frame.center) : nil) ?? currentWorkspace ?? freeSlot()
            join(id, to)
            if mode == .stack, let k = workspaceIndex(to) {
                workspaces[k].mode = .stack
                retile(to)
            }
            return isOverview ? follow(id) : reveal(id)
        }
        if mode == .tiles, ws.mode == .tiles {
            workspaces[k].orientation = isHorizontal(ws) ? .vertical : .horizontal
        } else {
            workspaces[k].mode = ws.mode == mode ? .tiles : mode
        }
        layoutRevision += 1
        retile(ws.slot)
    }

    /// ⌥. : tiled to floating, at its last floating frame if that was on this
    /// workspace, else its tile shrunk to 70%; floating to tiled as ⌥/.
    mutating func toggleFloating() {
        guard let i = target else { return }
        let id = windows[i].id
        guard let ws = workspace(of: id) else { return setLayout(.tiles) }
        checkpoint("layout", window: id)
        let tile = windows[i].frame
        leave(id)
        guard let j = index(id) else { return }
        var f: CGRect
        if let last = windows[j].floatingFrame, workspaceFrame(ws.slot).contains(last.center) {
            f = last
        } else {
            f = CGRect(x: 0, y: 0, width: tile.width * 0.7, height: tile.height * 0.7).centered(at: tile.center)
            if settings.snapEnabled { f = snapToGrid(f, grid: look.gridSize) }
        }
        windows[j].frame = f.roundedFrame
        raise(j)
        if !isOverview { sync([id]) }
    }

    /// ⌥1…⌥9: workspace `n` becomes current (even empty, so new windows join
    /// it) and its last used window gets focus. At 100% the camera settles on
    /// it; zoomed out it flies there and the selection follows.
    mutating func goToWorkspace(_ n: Int, focusing id: WindowID? = nil) {
        guard n >= 1 else { return }
        setCurrent(n)
        guard let k = workspaceIndex(n) else { return }
        let matches = isOverview ? overview.matchSet : nil // while searching, only a match can be picked
        let pick = id ?? mru.sorted(tiles(workspaces[k]).map(\.id).filter { matches?.contains($0) ?? true }).first
        if isOverview {
            fly(to: camera(framingWorkspace: n, maxZoom: animator.target.zoom))
            if let pick {
                selection = pick
                overview.selectWindow(pick)
            }
            return
        }
        cut(to: showWorkspace(n))
        if let pick, let i = index(pick) {
            raise(i)
            focusWindow(pick)
        }
    }

    /// ⌃← ⌃→ and three-finger swipes: the previous or next workspace with windows (or the current one).
    mutating func stepWorkspace(forward: Bool) {
        let pool = Set(workspaces.filter { !$0.members.isEmpty }.map(\.slot) + [currentWorkspace].compactMap { $0 }).sorted()
        guard !pool.isEmpty else { return }
        let at = currentWorkspace.flatMap { pool.firstIndex(of: $0) } ?? 0, next = at + (forward ? 1 : -1)
        // The ends stop, as AeroSpace's `workspace next|prev` without --wrap-around and a Spaces swipe do.
        guard pool.indices.contains(next) else { return }
        goToWorkspace(pool[next])
    }

    /// ⌥⇧1…⌥⇧9: the window joins workspace `n` and the camera follows it there.
    mutating func moveToWorkspace(_ n: Int, at position: Int? = nil) {
        guard n >= 1, let i = target else { return }
        let id = windows[i].id
        checkpoint("move", window: id)
        join(id, n, at: position)
        goToWorkspace(n, focusing: id)
    }

    /// ⌥⇧ arrows on a tiled window: it swaps with its neighbour that way (in
    /// a stack: moves in the order); past the ends, left and right take it to
    /// the workspace before or after, when moves cross workspaces.
    mutating func nudgeTile(_ id: WindowID, _ d: Direction) {
        guard let ws = workspace(of: id), let k = workspaceIndex(ws.slot) else { return }
        let shown = tiles(ws).map(\.id)
        if d.isHorizontal == isHorizontal(ws), let p = shown.firstIndex(of: id), shown.indices.contains(p + d.sign),
           let a = ws.members.firstIndex(of: id), let b = ws.members.firstIndex(of: shown[p + d.sign]) {
            checkpoint("nudge", window: id)
            workspaces[k].members.swapAt(a, b)
            layoutRevision += 1
            return retile(ws.slot)
        }
        guard d.isHorizontal, ws.slot + d.sign >= 1, !staysInWorkspace else { return }
        moveToWorkspace(ws.slot + d.sign, at: d == .right ? 0 : nil)
    }

    // MARK: Switcher (⌥Tab)

    mutating func switchWindow(forward: Bool) {
        // In a stack, ⌥Tab steps through its windows (wrapping) instead of the recent-windows picker; ⌘Tab does apps.
        if !isOverview, !overview.isOpen, let i = target, let ws = workspace(of: windows[i].id), ws.mode == .stack {
            let shown = tiles(ws).map(\.id)
            if shown.count > 1, let p = shown.firstIndex(of: windows[i].id) {
                return reveal(shown[(p + (forward ? 1 : -1) + shown.count) % shown.count])
            }
        }
        if isOverview {
            overview.moveSelection(forward ? 1 : -1)
            if let id = overview.selectedWindow { follow(id) }
            return
        }
        if !overview.isOpen { overview.begin(overviewContext, switcher: true, now: now) }
        overview.moveSelection(forward ? 1 : -1)
    }

    /// ⌥ released: the selected window gets focus; the camera goes to it
    /// only if it is not fully on screen.
    mutating func commitSwitcher() {
        guard overview.switcher else { return }
        let id = overview.selectedWindow
        if isOverview { return landOn(id) }
        overview.end()
        if let id { reveal(id) }
    }

    mutating func cancelSwitcher() {
        if isOverview { back() } else { overview.end() }
    }

    // MARK: Overview keys

    mutating func overviewInput(_ input: OverviewInput) {
        guard overview.isOpen else { return }
        applyOverview(overview.handle(input, overviewContext))
    }

    mutating func applyOverview(_ effects: [OverviewEffect]) {
        for effect in effects {
            switch effect {
            case let .follow(id): follow(id)
            case let .land(id): landOn(id)
            case let .summon(id): summon(id)
            case .revert: back()
            case let .action(a): perform(a)
            case .commitSwitcher: commitSwitcher()
            case .cancelSwitcher: cancelSwitcher()
            }
        }
    }
}

extension Direction {
    var isHorizontal: Bool { self == .left || self == .right }
    var sign: Int { self == .right || self == .down ? 1 : -1 }

    var vector: CGVector {
        switch self {
        case .left: CGVector(dx: -1, dy: 0)
        case .right: CGVector(dx: 1, dy: 0)
        case .up: CGVector(dx: 0, dy: -1)
        case .down: CGVector(dx: 0, dy: 1)
        }
    }
}

extension CGRect {
    /// `dw` wider and `dh` taller around the same center, never below 160 × 100.
    func resized(width dw: CGFloat, height dh: CGFloat) -> CGRect {
        CGRect(origin: .zero, size: CGSize(width: Swift.max(160, width + dw), height: Swift.max(100, height + dh))).centered(at: center)
    }
}
