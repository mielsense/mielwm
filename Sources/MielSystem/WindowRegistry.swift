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
        let now = Displays.screens(keeping: screens)
        guard now != screens else { return }
        screens = now
        onEvent(.screensChanged(now))
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

    /// Re-reads every app's window list, catching windows whose notifications
    /// were missed, and picks up apps that became regular after launch.
    public func refresh() {
        if pidFilter == nil { NSWorkspace.shared.runningApplications.forEach(track) }
        for tracker in trackers.values { tracker.queue.async { tracker.scan() } }
    }

    /// Fire and forget. Commands for one app run in order on its queue. The
    /// group finishes once every app has applied them; wait on it from any
    /// thread (quit and unpark, where the process may exit next).
    @discardableResult
    public func perform(_ commands: [WindowCommand]) -> DispatchGroup {
        let group = DispatchGroup()
        for (tracker, batch) in batches(commands) {
            group.enter()
            tracker.queue.async {
                tracker.run(batch)
                group.leave()
            }
        }
        return group
    }

    /// `perform`, then blocks until every app has applied the commands, at
    /// most `timeout` seconds. Returns false if some app did not finish in time.
    @discardableResult
    public func performAndWait(_ commands: [WindowCommand], timeout: TimeInterval = 2) -> Bool {
        perform(commands).wait(timeout: .now() + timeout) == .success
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
        trackers[pid]?.reportFocus()
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
        case .windowFrameChanged(let id, let frame):
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

extension WindowCommand {
    var window: WindowID {
        switch self {
        case .setFrame(let id, _), .focus(let id): id
        }
    }
}

// MARK: - One app

private let appNotifications = [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
                                kAXApplicationActivatedNotification]
private let windowNotifications = [kAXUIElementDestroyedNotification, kAXMovedNotification, kAXResizedNotification,
                                   kAXTitleChangedNotification, kAXWindowMiniaturizedNotification,
                                   kAXWindowDeminiaturizedNotification]

/// Not in the AX headers; AppKit windows report it, and so do most others.
private let kAXFullScreen = "AXFullScreen"

private let axCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    let tracker = Unmanaged<AppTracker>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    tracker.queue.async { tracker.handle(name, element) }
}

/// Everything below runs on `queue` unless noted.
final class AppTracker {
    let pid: pid_t
    let queue: DispatchQueue
    private let app: AXUIElement
    private let bundleID: String?
    private let appName: String
    private let observerThread: RunLoopThread
    private let post: (SystemEvent) -> Void

    private var observer: AXObserver?
    private var refcon: Unmanaged<AppTracker>?
    private var stopped = false
    private var elements: [WindowID: AXUIElement] = [:]
    private var ids: [AXUIElement: WindowID] = [:]
    private var fullScreen: Set<WindowID> = []
    private var sizes: [WindowID: CGSize] = [:] // last size read or written, so a move that keeps it sets only the position

    init(pid: pid_t, bundleID: String?, appName: String, observerThread: RunLoopThread,
         post: @escaping (SystemEvent) -> Void) {
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.observerThread = observerThread
        self.post = post
        app = AXUIElementCreateApplication(pid)
        queue = DispatchQueue(label: "mielwm.ax.\(pid)", qos: .userInitiated)
    }

    /// Any thread.
    func start() {
        queue.async { self.setUp(attempt: 0) }
    }

    /// Any thread. Leaves `group` once the observer can no longer call back.
    func stop(_ group: DispatchGroup? = nil) {
        group?.enter()
        queue.async {
            self.stopped = true
            guard let observer = self.observer, let refcon = self.refcon else {
                group?.leave()
                return
            }
            self.observer = nil
            self.refcon = nil
            let source = AXObserverGetRunLoopSource(observer)
            // On the observer thread itself, so no callback is mid-flight.
            self.observerThread.perform {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
                refcon.release()
                group?.leave()
            }
        }
    }

    private func setUp(attempt: Int) {
        guard !stopped else { return }
        AXUIElementSetMessagingTimeout(app, axTimeout)
        var created: AXObserver?
        guard AXObserverCreate(pid, axCallback, &created) == .success, let observer = created else { return }
        let refcon = Unmanaged.passRetained(self)
        let result = AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, refcon.toOpaque())
        guard result == .success else {
            refcon.release()
            // Apps that are still launching refuse for a while; apps without
            // AX support or a missing permission never stop refusing.
            if attempt < 20, result != .apiDisabled, result != .notImplemented {
                queue.asyncAfter(deadline: .now() + 0.25) { self.setUp(attempt: attempt + 1) }
            }
            return
        }
        for name in appNotifications.dropFirst() {
            AXObserverAddNotification(observer, app, name as CFString, refcon.toOpaque())
        }
        self.observer = observer
        self.refcon = refcon
        CFRunLoopAddSource(observerThread.runLoop, AXObserverGetRunLoopSource(observer), .defaultMode)
        scan()
    }

    func handle(_ name: String, _ element: AXUIElement) {
        switch name {
        case kAXWindowCreatedNotification:
            adopt(element)
        case kAXUIElementDestroyedNotification:
            guard let id = ids.removeValue(forKey: element) else { return }
            elements[id] = nil
            fullScreen.remove(id)
            sizes[id] = nil
            post(.windowClosed(id))
        case kAXMovedNotification, kAXResizedNotification:
            guard let id = ids[element], let (frame, isFullScreen) = frame(of: element) else { return }
            sizes[id] = frame.size
            let was = fullScreen.contains(id)
            let on = isFullScreen ?? was // a failed read changes nothing
            let changed = on != was
            if changed, on { // before the screen-sized frame, so Core does not take it for a resize
                fullScreen.insert(id)
                post(.windowFullScreen(id, true))
            }
            post(.windowFrameChanged(id, frame))
            if changed, !on { // after, so Core knows where macOS put it back
                fullScreen.remove(id)
                post(.windowFullScreen(id, false))
            }
        case kAXTitleChangedNotification:
            if let id = ids[element], let title = element.value(kAXTitleAttribute) as? String {
                post(.windowTitleChanged(id, title))
            }
        case kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification:
            if let id = ids[element] { post(.windowMinimized(id, name == kAXWindowMiniaturizedNotification)) }
        case kAXFocusedWindowChangedNotification, kAXApplicationActivatedNotification:
            postFocus()
        default:
            break
        }
    }

    /// Re-reads the window list: announces new windows, closes vanished ones.
    func scan() {
        guard observer != nil, let current = app.value(kAXWindowsAttribute) as? [AXUIElement] else { return }
        let live = Set(current.compactMap(adopt))
        for (id, element) in elements where !live.contains(id) {
            elements[id] = nil
            ids[element] = nil
            fullScreen.remove(id)
            sizes[id] = nil
            post(.windowClosed(id))
        }
    }

    /// Any thread.
    func reportFocus() {
        queue.async { self.postFocus() }
    }

    func run(_ batch: [WindowCommand]) {
        // With it on (VoiceOver, some automation tools), apps animate and
        // fight programmatic frame changes. It is per app: once per batch.
        let moves = batch.contains { if case .setFrame = $0 { true } else { false } }
        let enhanced = moves && app.value("AXEnhancedUserInterface") as? Bool == true
        if enhanced { app.set("AXEnhancedUserInterface", kCFBooleanFalse) }
        batch.forEach(run)
        if enhanced { app.set("AXEnhancedUserInterface", kCFBooleanTrue) }
    }

    private func run(_ command: WindowCommand) {
        switch command {
        case .setFrame(let id, let frame):
            // Core may have sent it before hearing the window went full screen.
            guard !fullScreen.contains(id), let window = element(id) else { return }
            // shortcut: an app that resizes a window without kAXResizedNotification keeps that size on
            // the next same-size move; set the size every time if such an app turns up.
            guard sizes[id] != frame.size else { // the same size: a move alone (parking, workspace switches)
                window.set(kAXPositionAttribute, axValue(frame.origin))
                return
            }
            // Size first so a move onto a smaller display is not clamped,
            // size again in case the old position limited the first one.
            window.set(kAXSizeAttribute, axValue(frame.size))
            window.set(kAXPositionAttribute, axValue(frame.origin))
            // A write that failed (a busy app timing out) leaves the size unknown, so the next move sets it again.
            sizes[id] = window.set(kAXSizeAttribute, axValue(frame.size)) == .success ? frame.size : nil
        case .focus(let id):
            guard let window = element(id) else { return }
            if window.value(kAXMinimizedAttribute) as? Bool == true { window.set(kAXMinimizedAttribute, kCFBooleanFalse) }
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            window.set(kAXMainAttribute, kCFBooleanTrue)
            app.set(kAXFocusedWindowAttribute, window)
            app.set(kAXFrontmostAttribute, kCFBooleanTrue)
            let pid = pid
            DispatchQueue.main.async { NSRunningApplication(processIdentifier: pid)?.activate() }
        }
    }

    private func postFocus() {
        guard let value = app.value(kAXFocusedWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID(),
              let id = adopt(value as! AXUIElement) else { return }
        post(.windowFocused(id))
    }

    private func element(_ id: WindowID) -> AXUIElement? {
        if elements[id] == nil { scan() }
        return elements[id]
    }

    @discardableResult
    private func adopt(_ element: AXUIElement) -> WindowID? {
        if let id = ids[element] { return id }
        guard let number = element.windowNumber else { return nil }
        let id = WindowID(pid: pid, number: number)
        if elements[id] != nil {
            ids[element] = id
            return id
        }
        guard let snapshot = snapshot(element, id) else { return nil }
        elements[id] = element
        ids[element] = id
        if snapshot.isFullScreen { fullScreen.insert(id) }
        sizes[id] = snapshot.frame.size
        if let observer, let refcon {
            for name in windowNotifications {
                AXObserverAddNotification(observer, element, name as CFString, refcon.toOpaque())
            }
        }
        post(.windowAppeared(snapshot))
        return id
    }

    /// shortcut: role and subrole are read once, when the window appears. If
    /// an app turns out to report AXUnknown first, re-read them on a later event.
    private func snapshot(_ element: AXUIElement, _ id: WindowID) -> WindowSnapshot? {
        let v = element.values([kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute,
                                kAXPositionAttribute, kAXSizeAttribute, kAXMinimizedAttribute, kAXFullScreen])
        guard let origin = cgPoint(v[3]), let size = cgSize(v[4]) else { return nil }
        return WindowSnapshot(id: id, bundleID: bundleID, appName: appName, title: v[2] as? String ?? "",
                              frame: CGRect(origin: origin, size: size), isMinimized: v[5] as? Bool ?? false,
                              isStandard: v[0] as? String == kAXWindowRole && v[1] as? String == kAXStandardWindowSubrole,
                              isResizable: element.isSettable(kAXSizeAttribute),
                              isMovable: element.isSettable(kAXPositionAttribute), isFullScreen: v[6] as? Bool ?? false)
    }

    /// The frame, and whether it is in full screen (nil when that read failed), in one round trip.
    private func frame(of element: AXUIElement) -> (CGRect, Bool?)? {
        let v = element.values([kAXPositionAttribute, kAXSizeAttribute, kAXFullScreen])
        guard let origin = cgPoint(v[0]), let size = cgSize(v[1]) else { return nil }
        return (CGRect(origin: origin, size: size), v[2] as? Bool)
    }
}
