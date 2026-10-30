import AppKit
import ApplicationServices
import MielCore

// One app's windows for WindowRegistry: its AX observer, its serial queue,
// the snapshots it reports and the commands it runs.

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
    nonisolated(unsafe) let element = element // AX elements are safe to use from any thread
    tracker.queue.async { tracker.handle(name, element) }
}

/// Everything below runs on `queue` unless noted, which is why it can be
/// shared between threads unchecked.
final class AppTracker: @unchecked Sendable {
    let pid: pid_t
    let queue: DispatchQueue
    private let app: AXUIElement
    private let bundleID: String?
    private let appName: String
    private let observerThread: RunLoopThread
    private let post: @Sendable (SystemEvent) -> Void

    private var observer: AXObserver?
    private var refcon: Unmanaged<AppTracker>?
    private var stopped = false
    private var elements: [WindowID: AXUIElement] = [:]
    private var ids: [AXUIElement: WindowID] = [:]
    private var fullScreen: Set<WindowID> = []
    /// Not standard or not movable when last read, so Core skips them. Rescans
    /// read them again: some apps report AXUnknown or AXDialog at first.
    private var ignored: Set<WindowID> = []
    private var sizes: [WindowID: CGSize] = [:] // last size read or written, so a move that keeps it sets only the position

    init(pid: pid_t, bundleID: String?, appName: String, observerThread: RunLoopThread,
         post: @escaping @Sendable (SystemEvent) -> Void) {
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

    private static let attempts = 20

    private func setUp(attempt: Int) {
        guard !stopped, observer == nil else { return }
        AXUIElementSetMessagingTimeout(app, axTimeout)
        var created: AXObserver?
        guard AXObserverCreate(pid, axCallback, &created) == .success, let observer = created else { return }
        let refcon = Unmanaged.passRetained(self)
        let result = AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, refcon.toOpaque())
        guard result == .success else {
            refcon.release()
            // Apps that are still launching refuse for a while; apps without
            // AX support or a missing permission never stop refusing.
            if attempt < Self.attempts, result != .apiDisabled, result != .notImplemented {
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
        // After its windows, so Core has them to hide. Later changes come from NSWorkspace.
        if app.value(kAXHiddenAttribute) as? Bool == true { post(.appHidden(pid: pid, true)) }
    }

    func handle(_ name: String, _ element: AXUIElement) {
        switch name {
        case kAXWindowCreatedNotification:
            adopt(element)
        case kAXUIElementDestroyedNotification:
            if let id = ids[element] { forget(id, element) }
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
            func since(_ type: CGEventType) -> Double { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type) }
            let dragging = isUserDrag(buttonDown: NSEvent.pressedMouseButtons & 1 != 0, sinceMouseDown: since(.leftMouseDown),
                                      sinceDrag: since(.leftMouseDragged), sinceMouseUp: since(.leftMouseUp))
            post(.windowFrameChanged(id, frame, dragging: dragging))
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

    /// Any thread. `scan`, or one more try for an app that refused to be watched.
    func rescan() {
        queue.async { self.observer == nil ? self.setUp(attempt: Self.attempts) : self.scan() } // a last attempt, no retries
    }

    /// Re-reads the window list: announces new windows and ignored ones that
    /// became standard, closes destroyed ones. A window missing from the list
    /// but still alive (on another Space, say) stays.
    func scan() {
        guard observer != nil, let current = app.value(kAXWindowsAttribute) as? [AXUIElement] else { return }
        let live = Set(current.compactMap(adopt))
        for (id, element) in elements where !live.contains(id) && element.isGone { forget(id, element) }
        for id in ignored.intersection(live) {
            guard let element = elements[id], let snapshot = snapshot(element, id), snapshot.isManageable else { continue }
            ignored.remove(id)
            if snapshot.isFullScreen { fullScreen.insert(id) }
            post(.windowAppeared(snapshot))
        }
    }

    private func forget(_ id: WindowID, _ element: AXUIElement) {
        elements[id] = nil
        ids[element] = nil
        fullScreen.remove(id)
        ignored.remove(id)
        sizes[id] = nil
        post(.windowClosed(id))
    }

    /// Any thread.
    func reportFocus() {
        queue.async { self.postFocus() }
    }

    /// False if the app did not answer some frame write in time.
    func run(_ batch: [WindowCommand]) -> Bool {
        // With it on (VoiceOver, some automation tools), apps animate and
        // fight programmatic frame changes. It is per app: once per batch.
        let moves = batch.contains { if case .setFrame = $0 { true } else { false } }
        let enhanced = moves && app.value("AXEnhancedUserInterface") as? Bool == true
        if enhanced { app.set("AXEnhancedUserInterface", kCFBooleanFalse) }
        let answered = batch.map(run).allSatisfy { $0 }
        if enhanced { app.set("AXEnhancedUserInterface", kCFBooleanTrue) }
        return answered
    }

    private func run(_ command: WindowCommand) -> Bool {
        switch command {
        case .setFrame(let id, let frame):
            // Core may have sent it before hearing the window went full screen.
            guard !fullScreen.contains(id), let window = element(id) else { return true }
            // shortcut: an app that resizes a window without kAXResizedNotification keeps that size on
            // the next same-size move; set the size every time if such an app turns up.
            guard sizes[id] != frame.size else { // the same size: a move alone (parking, workspace switches)
                return window.set(kAXPositionAttribute, axValue(frame.origin)) != .cannotComplete
            }
            // Size first so a move onto a smaller display is not clamped,
            // size again in case the old position limited the first one.
            let first = window.set(kAXSizeAttribute, axValue(frame.size))
            let moved = window.set(kAXPositionAttribute, axValue(frame.origin))
            let last = window.set(kAXSizeAttribute, axValue(frame.size))
            // A write that failed (a busy app timing out) leaves the size unknown, so the next move sets it again.
            sizes[id] = last == .success ? frame.size : nil
            return ![first, moved, last].contains(.cannotComplete) // what a timeout returns; a refused size is an answer
        case .focus(let id):
            guard let window = element(id) else { return true }
            if window.value(kAXMinimizedAttribute) as? Bool == true { window.set(kAXMinimizedAttribute, kCFBooleanFalse) }
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            window.set(kAXMainAttribute, kCFBooleanTrue)
            app.set(kAXFocusedWindowAttribute, window)
            app.set(kAXFrontmostAttribute, kCFBooleanTrue)
            let pid = pid
            DispatchQueue.main.async { NSRunningApplication(processIdentifier: pid)?.activate() }
            return true // nobody waits on focus
        case .close(let id):
            // The close button, as a click: the app may still ask to save first.
            guard let window = element(id), let button = window.value(kAXCloseButtonAttribute),
                  CFGetTypeID(button) == AXUIElementGetTypeID() else { return true }
            AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
            return true
        case .minimize(let id):
            element(id)?.set(kAXMinimizedAttribute, kCFBooleanTrue)
            return true
        }
    }

    private func postFocus() {
        guard let value = app.value(kAXFocusedWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID(),
              let id = adopt(value as! AXUIElement) else { return post(.unmanagedFocus(pid: pid)) } // the desktop, a sheet, a panel
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
        if !snapshot.isManageable { ignored.insert(id) }
        sizes[id] = snapshot.frame.size
        if let observer, let refcon {
            for name in windowNotifications {
                AXObserverAddNotification(observer, element, name as CFString, refcon.toOpaque())
            }
        }
        post(.windowAppeared(snapshot))
        return id
    }

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
