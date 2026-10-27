import Foundation

/// A thread that runs its own CFRunLoop, for event-tap and AXObserver sources
/// that must never wait on the main thread.
final class RunLoopThread: Thread {
    private(set) var runLoop: CFRunLoop!
    private let ready = DispatchSemaphore(value: 0)

    init(name: String) {
        super.init()
        self.name = name
        qualityOfService = .userInteractive
    }

    override func main() {
        runLoop = CFRunLoopGetCurrent()
        // A source with no callbacks keeps CFRunLoopRun from returning early.
        var context = CFRunLoopSourceContext()
        CFRunLoopAddSource(runLoop, CFRunLoopSourceCreate(nil, 0, &context), .defaultMode)
        ready.signal()
        CFRunLoopRun()
    }

    /// Starts the thread and returns once its run loop exists.
    func startAndWait() {
        start()
        ready.wait()
    }

    /// Runs `block` on this thread, between run-loop callbacks.
    func perform(_ block: @escaping () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    func stop() {
        perform { CFRunLoopStop(CFRunLoopGetCurrent()) }
    }
}
