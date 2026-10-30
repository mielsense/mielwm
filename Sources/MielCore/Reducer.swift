import CoreGraphics
import Foundation

/// Pointer gestures the app forwards, in desk points.
public enum PointerGesture: Hashable, Sendable {
    case pan(CGVector) // the pointer moved this far; the canvas follows it
    case panEnded(velocity: CGVector) // points per second at release, for momentum
    case zoom(at: CGPoint, factor: CGFloat) // wheel: exp(±zoomStep), a short glide
    case pinch(at: CGPoint, factor: CGFloat) // 1 + magnification (or a precise ⌘-scroll): follows the fingers, no glide
    case dragWindow(WindowID, CGVector)
    case resizeWindow(WindowID, Corner, CGVector)
    case dragEnded(WindowID)
    case minimapJump(CGPoint) // canvas point to center on

    public enum Corner: Hashable, Sendable { case topLeft, topRight, bottomLeft, bottomRight }
}

public enum CoreInput: Equatable, Sendable {
    case system(SystemEvent)
    case action(Action)
    case key(NamedKey, Modifiers) // while the overview or the switcher has the keyboard
    case text(String)
    case markedText(String)
    case modifiersChanged(Modifiers) // releasing ⌥ ends the switcher
    case gesture(PointerGesture)
    case tick(Double) // seconds on a monotonic clock
    case select(WindowID) // hover or click selection in the overview, camera stays
    case landOn(WindowID) // click a window in the overview
    case unparkAll // quit, toggle off, signals: every window back on a screen
    case setSettings(Settings) // config reloaded
}

/// The reducer: one input in, the next state and what System must do out.
public func reduce(_ state: CanvasState, _ input: CoreInput) -> (CanvasState, [WindowCommand]) {
    var next = state
    let commands = next.send(input)
    return (next, commands)
}

public extension CanvasState {
    /// Applies one input and returns the window commands it causes.
    mutating func send(_ input: CoreInput) -> [WindowCommand] {
        outbox = []
        let watch: NoticeWatch? = if case .tick = input { nil } else { noticeWatch }
        let wasOverview = isOverview
        switch input {
        case let .system(event): handle(event)
        case let .action(action): perform(action)
        case let .key(key, mods): overviewInput(.key(key, mods))
        case let .text(text): overviewInput(.text(text))
        case let .markedText(text): overviewInput(.markedText(text))
        case let .modifiersChanged(mods):
            if overview.switcher && !mods.contains(.option) { commitSwitcher() }
        case let .gesture(g): handle(g)
        case let .tick(time): tick(time)
        case let .select(id): // while searching, only a match can be picked
            if isOverview, index(id) != nil, overview.matchSet?.contains(id) ?? true {
                selection = id
                overview.selectWindow(id)
            }
        case let .landOn(id): landOn(id)
        case .unparkAll: unparkAll()
        case let .setSettings(s): settings = s
        }
        if let watch { updateNotices(from: watch) }
        // Leaving the overview without landing on a window gives the keyboard back to the one that had it.
        if wasOverview, !isOverview, let f = focused, !outbox.contains(where: \.isFocus) { focusWindow(f) }
        // One batch moves each window once: its last setFrame wins.
        var seen = Set<WindowID>()
        let out = outbox.reversed().filter { command in
            guard case let .setFrame(id, _) = command else { return true }
            return seen.insert(id).inserted
        }.reversed()
        outbox = []
        return Array(out)
    }

    /// Ticks are needed while this is true: animations, moves awaiting
    /// confirmation, the screen grace period, notices and toasts, the switcher's delay.
    var needsTicks: Bool { !animator.isSettled || notices.fading(at: now) || tickDeadline != nil }

    /// While nothing animates, ticks only wait for this: the earliest time a tick
    /// changes something (nil: never). nil too while something animates or a
    /// notice fades out, when every tick changes something.
    var tickDeadline: Double? {
        guard animator.isSettled, !notices.fading(at: now) else { return nil }
        let times = windows.compactMap(\.expected?.deadline) + notices.holds + [graceUntil, expectedFocus?.until,
                                                                                 overview.switcherRevealAt.flatMap { $0 > now ? $0 : nil }].compactMap { $0 }
        return times.min()
    }

    /// The overlay must be up: zoomed out, panning at full size, flying, or
    /// the ⌥Tab strip showing.
    var needsOverlay: Bool {
        isOverview || isPanning || !animator.isSettled || overview.switcherRevealed(now: now)
    }

    /// When a window waits to go back where it belongs. Not a reason to
    /// tick meanwhile, nor to keep the overview's frames awake.
    var nextRetry: Double? { windows.compactMap(\.retryAt).min() }

    enum TickPlan: Equatable { case none, everyFrame, once(at: Double) }

    /// The ticks the app sends without an overlay's frames: every frame while
    /// something animates, else one at the earliest deadline. A shown overlay
    /// ticks with its frames, which pause when only a retry is left.
    func tickPlan(overlayShown: Bool) -> TickPlan {
        if !overlayShown, !animator.isSettled || notices.fading(at: now) { return .everyFrame }
        let due = [overlayShown ? nil : tickDeadline, nextRetry].compactMap { $0 }.min()
        return due.map { .once(at: $0) } ?? .none
    }

    /// Some setFrame we sent is not confirmed yet (the landing fade waits for it).
    var movesInFlight: Bool { windows.contains { $0.expected != nil } }
}

extension CanvasState {
    // MARK: - Time

    mutating func tick(_ time: Double) {
        now = max(now, time)
        animator.step(to: now)
        for i in windows.indices {
            guard let e = windows[i].expected, now > e.deadline else { continue }
            windows[i].expected = nil
            if let report = windows[i].pending {
                windows[i].pending = nil
                judge(i, report, answering: true)
            } else if !e.resent, !windows[i].real.isClose(to: e.frame, tolerance: Self.frameTolerance) {
                setFrame(i, e.frame) // no report at all: the app may have dropped it, so once more
                windows[i].expected?.resent = true
            }
        }
        for i in windows.indices {
            guard let t = windows[i].retryAt, now >= t else { continue }
            windows[i].retryAt = nil
            windows[i].reparkedAt = now // the app's answer to this try counts on from it
            sync([windows[i].id], force: true)
        }
        if let g = graceUntil, now >= g { // the screens settled: put everything where it belongs
            graceUntil = nil
            for i in windows.indices { windows[i].expected = nil; windows[i].pending = nil; windows[i].sent = [] }
            sync(force: true)
        }
        notices.expire(now)
        if let f = expectedFocus, now >= f.until {
            expectedFocus = nil
            if let report = heldFocus { // focus changed again while ours landed: that is where it is now
                heldFocus = nil
                handle(report)
            }
        }
    }

    // MARK: - System events

    mutating func handle(_ event: SystemEvent) {
        defer {
            refocusIfLost() // the focused window may have closed, minimized or hidden
            // The search list follows windows coming, going and being renamed.
            switch event {
            case .windowFrameChanged, .windowFocused, .unmanagedFocus, .screensChanged: break
            default:
                if overview.isOpen {
                    overview.rebuild(overviewContext, resetSelection: false)
                    if isOverview, selection == nil { selection = overview.selectedWindow }
                }
            }
        }
        switch event {
        case let .windowAppeared(snapshot): appeared(snapshot)
        case let .unmanagedFocus(pid): focusLeft(pid)
        case let .windowClosed(id): remove { $0.id == id }
        case let .windowFrameChanged(id, frame, dragging): frameChanged(id, frame, dragging: dragging)
        case let .windowTitleChanged(id, title):
            guard let i = index(id) else { return }
            windows[i].title = title
        case let .windowMinimized(id, minimized):
            guard let i = index(id) else { return }
            windows[i].isMinimized = minimized
            retile(windows[i].workspace) // a minimized window gives up its tile
            if !minimized { sync([id]); focusPending() }
        case let .windowFullScreen(id, on):
            guard let i = index(id) else { return }
            windows[i].isFullScreen = on
            windows[i].expected = nil
            windows[i].pending = nil
            guard !on else { return }
            // A tiled one goes to its tile, should it have changed meanwhile. A floating one stays
            // where macOS put it back: mielwm may never have known its size out of full screen.
            if windows[i].workspace == nil { judge(i, windows[i].real, answering: false) } else { sync([id]) }
        case let .windowFocused(id): focusedFromOutside(id)
        case let .appHidden(pid, hidden):
            for i in windows.indices where windows[i].id.pid == pid { windows[i].isHidden = hidden }
            for slot in Set(windows.filter { $0.id.pid == pid }.compactMap(\.workspace)) { retile(slot) }
            if !hidden { sync(Set(windows.filter { $0.id.pid == pid }.map(\.id))); focusPending() }
        case let .appTerminated(pid): remove { $0.id.pid == pid }
        case let .screensChanged(new): screensChanged(new)
        }
    }

    mutating func remove(where match: (ManagedWindow) -> Bool) {
        let gone = windows.filter(match).map(\.id)
        guard !gone.isEmpty else { return }
        windows.removeAll(where: match)
        for id in gone {
            mru.remove(id)
            fills[id] = nil
            fullscreens[id] = nil
            if selection == id { selection = nil }
            if dragging == id { dragging = nil; dropIndicator = nil }
            leave(id) // the rest of its workspace tiles again
        }
        layoutRevision += 1
    }

    /// The focused window closed, minimized or hid. macOS focuses a window of
    /// its choosing, often one parked on another workspace, so the most
    /// recent window on screen takes focus instead. With none, nothing does
    /// and macOS's pick is ignored for a moment: the camera stays.
    mutating func refocusIfLost() {
        guard let f = focused, !(window(f)?.isShown ?? false) else { return }
        focused = nil
        if let next = mru.sorted(windows.filter { $0.isShown && isFullyVisible($0) }.map(\.id)).first {
            focusWindow(next)
        } else {
            expectedFocus = (f, now + Self.focusLifetime) // a focus nobody gets, to hold off the others
        }
    }

    /// A new window: a saved spot (and workspace) wins; one found in a
    /// park corner (ours or AeroSpace's) or off every screen goes near the
    /// camera without overlap; anything else stays where it is. Then it joins
    /// a workspace or floats (see `placement`).
    mutating func appeared(_ s: WindowSnapshot) {
        guard s.isManageable else { return }
        if let i = index(s.id) {
            windows[i].title = s.title
            windows[i].appName = s.appName
            windows[i].bundleID = s.bundleID
            windows[i].isMinimized = s.isMinimized
            windows[i].isFullScreen = s.isFullScreen
            windows[i].isResizable = s.isResizable
            windows[i].real = s.frame
            return
        }
        var w = ManagedWindow(id: s.id, bundleID: s.bundleID, appName: s.appName, title: s.title, frame: s.frame,
                              isMinimized: s.isMinimized, isFullScreen: s.isFullScreen, isResizable: s.isResizable, real: s.frame)
        let ordinal = windows.filter { $0.bundleID == s.bundleID && $0.displayTitle == w.displayTitle }.count
        var restored: SavedWindow?
        if now < restoreUntil, let saved, let k = saved.match(id: s.id, bundleID: s.bundleID, title: w.displayTitle, ordinal: ordinal, excluding: claimed) {
            claimed.insert(k)
            w.frame = saved.windows[k].frame
            if saved.version >= 2 { restored = saved.windows[k] } // older layouts knew no workspaces
        } else if settings.autoPlace, isHiddenFrame(s.frame, screens: screens) {
            let anchor = deskCamera.toCanvas(activeScreen.visibleFrame.center, deskCenter: deskCenter)
            w.frame = autoPlace(size: s.frame.size, around: anchor, occupied: candidates.map(\.frame), gap: settings.placementGap,
                                screenSize: activeScreen.visibleFrame.size, grid: settings.snapEnabled ? look.gridSize : nil)
        } else {
            w.frame = deskCamera.toCanvas(s.frame, deskCenter: deskCenter)
        }
        windows.append(w)
        if let restored {
            if let slot = restored.workspace {
                let position = restored.position ?? .max
                restoredPositions[s.id] = position
                let k = ensureWorkspace(slot)
                join(s.id, slot, at: workspaces[k].members.filter { (restoredPositions[$0] ?? .max) <= position }.count,
                     weight: restored.weight)
            }
        } else if let (slot, position) = placement(for: s) {
            join(s.id, slot, at: position)
        }
        sync([s.id])
        layoutRevision += 1
    }

    /// Our own moves come back as reports: one that matches what we asked
    /// for is ignored, never adopted. While an expectation lives (size, then
    /// position, then size again gives three reports) only the newest report
    /// is kept, and judged if the expectation lapses without a match. A late
    /// report of an earlier move of ours (a busy app, many windows moving at
    /// once) is ignored too, unless the user is dragging or the window is parked.
    mutating func frameChanged(_ id: WindowID, _ frame: CGRect, dragging: Bool) {
        guard let i = index(id) else { return }
        windows[i].real = frame
        if windows[i].isFullScreen { return } // the screen-sized frame is not a resize to adopt
        if graceUntil != nil { return } // macOS shuffles windows while screens change
        let live = windows[i].expected.flatMap { now <= $0.deadline ? $0 : nil }
        if let live, frame.isClose(to: live.frame, tolerance: Self.frameTolerance) {
            windows[i].expected = nil
            windows[i].pending = nil
            return
        }
        // Not for a parked window: an app pulling it back to a frame we set before is the fight `judge` handles.
        if !dragging, !windows[i].parked, windows[i].sent.contains(where: { now <= $0.deadline && frame.isClose(to: $0.frame, tolerance: Self.frameTolerance) }) {
            return
        }
        if live != nil {
            windows[i].pending = frame
            return
        }
        windows[i].expected = nil
        judge(i, frame, answering: false, dragging: dragging)
    }

    /// A report that did not match: the newest one left when a move we
    /// asked for lapsed (`answering`), or one nobody asked for, `dragging` when the mouse button was down.
    mutating func judge(_ i: Int, _ frame: CGRect, answering: Bool, dragging: Bool = false) {
        let id = windows[i].id
        if windows[i].pinned != nil { // moved while pinned: it stays pinned there
            windows[i].pinned = frame
            return
        }
        let sameSize = frame.size.isClose(to: windows[i].frame.size, tolerance: Self.frameTolerance)
        if windows[i].parked {
            // Another report of its own slot (repeats, stray moves) confirms the park.
            if frame.isClose(to: desiredFrame(windows[i]).frame, tolerance: Self.frameTolerance) { return }
            // An app pulled a parked window back, or resized it: keep the
            // new size and park it again. After two tries in a row, wait 1, 2,
            // 4, 8 and 16 seconds before the next, then leave it until the
            // camera moves again: it still belongs off screen.
            if !sameSize { windows[i].frame.size = frame.size }
            let n = countRepark(i)
            if n <= Self.maxReparks {
                sync([id], force: true)
            } else if windows[i].retryAt == nil, n <= Self.maxReparks + Self.maxRetries {
                windows[i].retryAt = now + pow(2, Double(n - Self.maxReparks - 1))
            }
            return
        }
        if answering {
            // macOS clamped our move (below the menu bar, onto a screen):
            // the canvas frame stays. A size it would not take is adopted.
            if !sameSize {
                windows[i].frame.size = frame.size
                if fills[id].map({ !frame.size.isClose(to: $0.filled.size) }) ?? false { fills[id] = nil }
                layoutRevision += 1
            }
            return
        }
        // The user dragged it, or the app moved or resized itself: adopt.
        // A tiled window keeps its tile, or the user drags the edge it shares with a neighbour.
        if windows[i].workspace != nil {
            if dragging, sameSize { // by its title bar: back once the reports stop, without counting as a try
                windows[i].retryAt = now + dragGrace
                return
            }
            return userChangedTile(i, to: deskCamera.toCanvas(frame, deskCenter: deskCenter), resizing: dragging)
        }
        windows[i].frame = deskCamera.toCanvas(frame, deskCenter: deskCenter)
        if fills[id].map({ !frame.size.isClose(to: $0.filled.size) }) ?? false { fills[id] = nil }
        layoutRevision += 1
    }

    /// Focus from outside (Cmd-Tab, the Dock, a click, an app raising
    /// itself). A window on screen stays where it is; one off camera or
    /// parked brings the camera to it. Our own windows don't count, nor do
    /// stray reports while a focus we asked for lands: the last one waits,
    /// and applies after, unless ours reports in later.
    mutating func focusedFromOutside(_ id: WindowID) {
        guard id.pid != ownPID else { return }
        if let f = expectedFocus, f.id != id, now < f.until { heldFocus = .windowFocused(id); return }
        heldFocus = nil // ours landed, or there was none
        guard let i = index(id), windows[i].isShown else { // a dialog or sheet, say, or a window about to show
            if expectedFocus?.id == id { expectedFocus = nil } // ours reported in before it shows: nothing to hold back
            focusLeft(id.pid)
            if index(id) != nil { pendingFocus = id } // macOS can report focus before the unhide or unminimize
            return
        }
        pendingFocus = nil
        focused = id
        mru.note(id)
        raise(i)
        guard let w = window(id) else { return }
        if isOverview {
            overview.selectWindow(id)
            follow(id)
        } else if w.pinned == nil, !isFullyVisible(w) {
            cut(to: landingCamera(id))
        }
    }

    /// Focus went to something mielwm doesn't manage (no window, or one it
    /// leaves alone): no managed window has it, so
    /// window keys do nothing rather than act on the last one. mielwm's own
    /// windows (the overview, Settings) keep it; while a focus we asked for
    /// lands, the report waits like any other.
    mutating func focusLeft(_ pid: Int32) {
        guard pid != ownPID, !isOverview, !overview.isOpen else { return }
        if expectedFocus.map({ now < $0.until }) == true { heldFocus = .unmanagedFocus(pid: pid); return }
        focused = nil
        pendingFocus = nil
    }

    /// The window last reported focused while it was not shown, now that it is.
    mutating func focusPending() {
        if let id = pendingFocus, window(id)?.isShown == true { focusedFromOutside(id) }
    }

    /// Screens came or went: keep canvas frames and the camera's offset
    /// from the desk, ignore reports for a moment, lay everything out again.
    mutating func screensChanged(_ new: [ScreenInfo]) {
        let old = deskCenter, oldScreens = screens
        screens = new
        let shift = CGVector(dx: deskCenter.x - old.x, dy: deskCenter.y - old.y)
        moveCameras { Camera(center: CGPoint(x: $0.center.x + shift.dx, y: $0.center.y + shift.dy), zoom: $0.zoom) }
        if let id = activeScreenID, !new.contains(where: { $0.id == id }) { activeScreenID = nil }
        for k in workspaces.indices where !new.contains(where: { $0.id == workspaces[k].screenID }) {
            workspaces[k].screenID = nil // its screen left: it lays out for the primary one
            retile(workspaces[k].slot)
        }
        widenSlots()
        for ws in workspaces { // a status bar came or went: the Automatic top gap follows
            let screen = layoutScreen(ws)
            if let before = oldScreens.first(where: { $0.id == screen.id }), before.topBar != screen.topBar { retile(ws.slot) }
        }
        graceUntil = now + Self.screenGracePeriod
        sync()
    }

    /// Every managed window to a frame some screen shows, including
    /// parked ones that are minimized or whose app is hidden.
    mutating func unparkAll() {
        for i in windows.indices where windows[i].isShown || windows[i].parked {
            let source = windows[i].parked ? deskCamera.toDesk(windows[i].frame, deskCenter: deskCenter) : windows[i].real
            let target = onScreenFrame(source, screens: screens).roundedFrame
            windows[i].parked = false
            if !target.isClose(to: windows[i].expected?.frame ?? windows[i].real, tolerance: 0.5) { setFrame(i, target) }
        }
    }

    // MARK: - Camera moves

    /// Every camera, at rest or flying, through `moved`.
    mutating func moveCameras(_ moved: (Camera) -> Camera) {
        deskCamera = moved(deskCamera)
        returnCamera = returnCamera.map(moved)
        let target = moved(animator.target)
        animator.warp(to: moved(animator.camera), now: now)
        animator.fly(to: target, now: now)
    }

    mutating func fly(to camera: Camera, transition: Double? = nil, velocity: CGVector? = nil) {
        animator.fly(to: camera, transition: transition, now: now, velocity: velocity)
    }

    /// `settle` with no flight: the camera is just there, like switching in AeroSpace.
    mutating func cut(to camera: Camera) {
        animator.warp(to: roundedAtRest(camera), now: now)
        settle(at: camera)
    }

    /// At rest at full size on `camera`: the real windows follow.
    mutating func settle(at camera: Camera, velocity: CGVector? = nil) {
        let c = roundedAtRest(camera)
        fly(to: c, transition: 0, velocity: velocity)
        if c != deskCamera { layoutRevision += 1 }
        deskCamera = c
        if let rest = restingSlot(c) { // resting on a workspace makes it current, laid out for that screen
            setCurrent(rest.slot)
            if let k = workspaceIndex(rest.slot), workspaces[k].screenID != rest.screen.id {
                workspaces[k].screenID = rest.screen.id
                retile(rest.slot)
            }
        }
        sync()
    }

    // MARK: - Gestures

    mutating func handle(_ g: PointerGesture) {
        switch g {
        case let .pan(delta):
            if !isOverview { isPanning = true }
            let c = animator.camera, k = settings.panSensitivity / c.zoom
            let moved = Camera(center: CGPoint(x: c.center.x - delta.dx * k, y: c.center.y - delta.dy * k), zoom: c.zoom)
            animator.warp(to: moved, now: now)
        case let .panEnded(velocity):
            let c = animator.camera, k = settings.panSensitivity / c.zoom
            let v = CGVector(dx: -velocity.dx * k, dy: -velocity.dy * k)
            let glide = 0.15 // seconds of momentum
            let target = Camera(center: CGPoint(x: c.center.x + v.dx * glide, y: c.center.y + v.dy * glide), zoom: c.zoom)
            if isOverview { fly(to: target, velocity: v) } else { settle(at: target, velocity: v) }
            isPanning = false
        case let .zoom(point, factor):
            if !isOverview { // zooming out at 100% opens the overview there
                return factor < 1 ? openOverview(zoom: animator.target.zoom * factor, at: point) : ()
            }
            fly(to: zoomed(animator.target, at: point, to: animator.target.zoom * factor))
        case let .pinch(point, factor):
            guard isOverview else { return handle(.zoom(at: point, factor: factor)) }
            animator.warp(to: zoomed(animator.camera, at: point, to: animator.camera.zoom * factor), now: now)
        case let .dragWindow(id, delta):
            guard let i = index(id) else { return }
            if dragging != id {
                checkpoint("drag", window: id)
                dragging = id
            }
            let z = isOverview ? animator.camera.zoom : 1
            if windows[i].pinned != nil {
                windows[i].pinned = windows[i].pinned!.offsetBy(delta)
            } else {
                windows[i].frame = windows[i].frame.offsetBy(dx: delta.dx / z, dy: delta.dy / z)
            }
            let spot = windows[i].workspace != nil ? dropSpot(i) : nil
            dropIndicator = isOverview ? spot?.tile ?? (settings.snapEnabled ? snapToGrid(windows[i].frame, grid: look.gridSize) : nil) : nil
            if !isOverview { sync([id]) }
        case let .resizeWindow(id, corner, delta):
            guard let i = index(id), windows[i].isResizable, windows[i].pinned == nil else { return }
            if dragging != id {
                checkpoint("resize", window: id)
                dragging = id
            }
            let z = isOverview ? animator.camera.zoom : 1
            let dx = delta.dx / z, dy = delta.dy / z
            var f = windows[i].frame
            let left = corner == .topLeft || corner == .bottomLeft, top = corner == .topLeft || corner == .topRight
            let w = max(120, f.width + (left ? -dx : dx)), h = max(80, f.height + (top ? -dy : dy))
            if left { f.origin.x = f.maxX - w }
            if top { f.origin.y = f.maxY - h }
            f.size = CGSize(width: w, height: h)
            windows[i].frame = f
            fills[id] = nil
            if !isOverview { sync([id]) }
        case let .dragEnded(id):
            guard let i = index(id) else { return }
            if let ws = workspace(of: id), let tile = tiles(ws).first(where: { $0.id == id })?.frame {
                dragging = nil
                dropIndicator = nil
                if !windows[i].frame.size.isClose(to: tile.size) { return userChangedTile(i, to: windows[i].frame, resizing: true) } // resized
                // Dropped on a workspace: it moves there (or within it); on open canvas it floats there.
                if let spot = dropSpot(i) { return join(id, spot.slot, at: spot.position) }
                leave(id)
            }
            if isOverview, settings.snapEnabled, windows[i].pinned == nil {
                windows[i].frame = snapToGrid(windows[i].frame, grid: look.gridSize)
            }
            dragging = nil
            dropIndicator = nil
            if !isOverview { sync([id]) }
            layoutRevision += 1
        case let .minimapJump(p):
            fly(to: camera(showing: p, atScreenPoint: overviewFreeArea(on: activeScreen).center, on: activeScreen, zoom: animator.target.zoom))
        }
    }

    // MARK: - Undo

    mutating func checkpoint(_ kind: String, window: WindowID? = nil) {
        // A held nudge key is one step to undo.
        if let last = lastCheckpoint, last.kind == kind, last.window == window, kind == "nudge", now - last.time < 0.6 {
            lastCheckpoint?.time = now
            return
        }
        lastCheckpoint = Checkpoint(kind: kind, window: window, time: now)
        undoStack.append(undoEntry)
        if undoStack.count > Self.undoDepth { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    var undoEntry: UndoEntry {
        UndoEntry(frames: Dictionary(windows.map { ($0.id, $0.frame) }, uniquingKeysWith: { a, _ in a }), workspaces: workspaces)
    }

    /// Undo (or redo): swaps frames and workspaces with the other stack's.
    mutating func undo(redo: Bool) -> Bool {
        guard let snapshot = redo ? redoStack.popLast() : undoStack.popLast() else { return false }
        if redo { undoStack.append(undoEntry) } else { redoStack.append(undoEntry) }
        for i in windows.indices { if let f = snapshot.frames[windows[i].id] { windows[i].frame = f } }
        let alive = Set(windows.map(\.id))
        workspaces = snapshot.workspaces.map { ws in
            var ws = ws
            ws.members.removeAll { !alive.contains($0) } // closed since
            return ws
        }
        let slotOf = Dictionary(workspaces.flatMap { ws in ws.members.map { ($0, ws.slot) } }, uniquingKeysWith: { a, _ in a })
        for i in windows.indices { windows[i].workspace = slotOf[windows[i].id] }
        if let c = currentWorkspace { setCurrent(c) }
        retileAll()
        lastCheckpoint = nil
        if !isOverview { sync() }
        layoutRevision += 1
        return true
    }
}
