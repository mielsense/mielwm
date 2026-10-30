import AppKit
import ApplicationServices
import MielCore

/// Finds the windows of regular apps over Accessibility, watches them, and
/// moves and focuses them on request.
///
/// Threading: every AX call for an app runs on that app's serial queue, so a
/// hung app only stalls itself (0.25 s per call). AXObserver callbacks arrive
/// on a private run-loop thread. Events reach `onEvent` on the main queue, in
/// the order each app reported them. Call the public methods on the main
/// thread; none of them waits on an app except `performAndWait`.
public final class WindowRegistry {
    /// Only this pid's windows (`--manage-only`, tests), whatever its
    /// activation policy. nil tracks every regular app except our own.
    public let pidFilter: Int32?
    /// Last known state of every announced window, updated from the events.
    public private(set) var windows: [WindowID: WindowSnapshot] = [:]

    private let onEvent: (SystemEvent) -> Void
    private var trackers: [pid_t: AppTracker] = [:]
    private let observerThread = RunLoopThread(name: "mielwm.ax-observers")
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var activePid: pid_t?
    private var lastFocused: WindowID?
    private var screens: [ScreenInfo] = []
    private var screenCheck: DispatchWorkItem?

    public init(pidFilter: Int32? = nil, onEvent: @escaping (SystemEvent) -> Void) {
        self.pidFilter = pidFilter
        self.onEvent = onEvent
    }

    /// Announces every existing window (`windowAppeared`), then the focused
    /// one, then reports changes as they happen. Screens are not announced:
    /// read `Displays.screens()`; later changes arrive as `screensChanged`.
    /// Call once; `stop()` ends the registry for good.
    public func start() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), axTimeout)
        observerThread.startAndWait()
        screens = Displays.screens()

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didLaunchApplicationNotification) { [weak self] app in
            self?.track(app)
            self?.checkScreensSoon()
        }
        observe(workspace, NSWorkspace.didTerminateApplicationNotification) { [weak self] app in
            self?.untrack(app.processIdentifier)
            self?.checkScreensSoon()
        }
        // Leaving a full screen Space shows a bar that was hidden there.
        let spaces = workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.checkScreensSoon()
        }
        tokens.append((workspace, spaces))
        observe(workspace, NSWorkspace.didHideApplicationNotification) { [weak self] app in
            self?.deliver(.appHidden(pid: app.processIdentifier, true))
        }
        observe(workspace, NSWorkspace.didUnhideApplicationNotification) { [weak self] app in
            self?.deliver(.appHidden(pid: app.processIdentifier, false))
        }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] app in
            self?.track(app) // it may have become regular since launch
            self?.activated(app.processIdentifier)
        }
        let token = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.checkScreens()
            self?.checkScreensSoon() // a status bar moves its window after the change
        }
        tokens.append((NotificationCenter.default, token))

        if let pid = pidFilter {
            NSRunningApplication(processIdentifier: pid).map(track)
        } else {
            NSWorkspace.shared.runningApplications.forEach(track)
        }
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier { activated(pid) }
    }

    private func checkScreens() {
        report(Displays.screens(keeping: screens))
    }

    /// Once things settle: a status bar app shows its window a moment after it starts.
    private func checkScreensSoon() {
        screenCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.checkScreens() }
        screenCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    public func stop() {
        screenCheck?.cancel()
        for (center, token) in tokens { center.removeObserver(token) }
        tokens = []
        let group = DispatchGroup()
        trackers.values.forEach { $0.stop(group) }
        trackers = [:]
        group.notify(queue: .global()) { [thread = observerThread] in thread.stop() }
    }

    /// `rescan`, after picking up apps that became regular after launch.
    /// Costs a few milliseconds on the main thread with many apps running.
    public func refresh() {
        if pidFilter == nil { NSWorkspace.shared.runningApplications.forEach(track) }
        rescan()
    }

    /// Re-reads the window list of every tracked app, catching windows whose
    /// notifications were missed. The reading happens on each app's queue;
    /// only the differences are reported.
    public func rescan() {
        trackers.values.forEach { $0.rescan() }
    }

    /// After waking: macOS has moved windows while displays went and came.
    /// Reports the screens even when they look the same, so Core waits out its
    /// grace period and then puts every window back, and rereads every window list.
    public func woke() {
        report(Displays.screens(keeping: screens), always: true)
        rescan()
    }

    /// Through the cache, so a change and the change back are both reported.
    func report(_ now: [ScreenInfo], always: Bool = false) {
        guard always || now != screens else { return }
        screens = now
        onEvent(.screensChanged(now))
    }

    /// Fire and forget. Commands for one app run in order on its queue. Wait
    /// on the result from any thread (quit and unpark, where the process may exit next).
    @discardableResult
    public func perform(_ commands: [WindowCommand]) -> Applied {
        let applied = Applied()
        for (tracker, batch) in batches(commands) {
            applied.group.enter()
            tracker.queue.async { applied.finish(answered: tracker.run(batch)) }
        }
        return applied
    }

    /// `perform`, then blocks until every app has applied the commands, at
    /// most `timeout` seconds. See `Applied.wait` for when it returns false.
    @discardableResult
    public func performAndWait(_ commands: [WindowCommand], timeout: TimeInterval = 2) -> Bool {
        perform(commands).wait(timeout: timeout)
    }

    // MARK: - Private

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ handler: @escaping (NSRunningApplication) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { handler(app) }
        }
        tokens.append((center, token))
    }

    private func track(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard trackers[pid] == nil, pid != getpid(),
              pidFilter.map({ $0 == pid }) ?? (app.activationPolicy == .regular) else { return }
        let tracker = AppTracker(pid: pid, bundleID: app.bundleIdentifier, appName: app.localizedName ?? "",
                                 observerThread: observerThread) { [weak self] event in
            DispatchQueue.main.async { self?.deliver(event) }
        }
        trackers[pid] = tracker
        tracker.start()
    }

    private func untrack(_ pid: pid_t) {
        guard let tracker = trackers.removeValue(forKey: pid) else { return }
        tracker.stop()
        windows = windows.filter { $0.key.pid != pid }
        onEvent(.appTerminated(pid: pid))
    }

    private func activated(_ pid: pid_t) {
        activePid = pid
        lastFocused = nil
        if let tracker = trackers[pid] {
            tracker.reportFocus() // first: it adopts the focused window on its own
            tracker.rescan()
        } else {
            deliver(.unmanagedFocus(pid: pid))
        }
    }

    /// Keeps `windows` current and drops what Core must never see: events
    /// for apps that are gone, for windows never announced, and focus
    /// reports from apps that are not frontmost.
    private func deliver(_ event: SystemEvent) {
        switch event {
        case .windowAppeared(let snapshot):
            guard trackers[snapshot.id.pid] != nil else { return }
            windows[snapshot.id] = snapshot
        case .windowClosed(let id):
            guard windows.removeValue(forKey: id) != nil else { return }
        case .windowFrameChanged(let id, let frame, _):
            guard windows[id] != nil else { return }
            windows[id]?.frame = frame
        case .windowTitleChanged(let id, let title):
            guard windows[id] != nil else { return }
            windows[id]?.title = title
        case .windowMinimized(let id, let minimized):
            guard windows[id] != nil else { return }
            windows[id]?.isMinimized = minimized
        case .windowFullScreen(let id, let on):
            guard windows[id] != nil else { return }
            windows[id]?.isFullScreen = on
        case .windowFocused(let id):
            guard id.pid == activePid, id != lastFocused, windows[id] != nil else { return }
            lastFocused = id
        case .unmanagedFocus(let pid):
            guard pid == activePid else { return }
            lastFocused = nil // coming back to the same window is news again
        case .appHidden(let pid, _):
            guard trackers[pid] != nil else { return }
        case .appTerminated, .screensChanged:
            break
        }
        onEvent(event)
    }

    /// Per app, in the order given; apps run concurrently, so their order does not matter.
    private func batches(_ commands: [WindowCommand]) -> [(AppTracker, [WindowCommand])] {
        Dictionary(grouping: commands, by: \.window.pid).compactMap { pid, batch in trackers[pid].map { ($0, batch) } }
    }
}

/// What `perform` sent. Thread-safe.
public final class Applied: @unchecked Sendable {
    fileprivate let group = DispatchGroup()
    private let lock = NSLock()
    private var unanswered = false

    fileprivate func finish(answered: Bool) {
        lock.withLock { if !answered { unanswered = true } }
        group.leave()
    }

    /// Blocks until every app has run its commands, at most `timeout` seconds.
    /// False if some app did not finish in time or did not answer a write: a
    /// hung app times each one out quickly, without moving anything.
    public func wait(timeout: TimeInterval) -> Bool {
        group.wait(timeout: .now() + timeout) == .success && lock.withLock { !unanswered }
    }
}

extension WindowCommand {
    var window: WindowID {
        switch self {
        case .setFrame(let id, _), .focus(let id), .close(let id), .minimize(let id): id
        }
    }
}
