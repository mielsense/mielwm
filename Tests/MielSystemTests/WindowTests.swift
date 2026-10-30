// Real macOS: opens throwaway windows (mielwm-testwindows) and drives them
// through WindowRegistry, CaptureManager and EventTap. Off by default; run
//   swift build && MIELWM_SYSTEM_TESTS=1 swift test --filter WindowTests
// Only ever touches windows of the helper process it launched. Writes the
// AX event sequences it sees to Fixtures/ for the Core reducer.

import ApplicationServices
import CoreVideo
import Foundation
import MielCore
@testable import MielSystem
import Testing

private let enabled = ProcessInfo.processInfo.environment["MIELWM_SYSTEM_TESTS"] == "1"
private let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
private let packageDir = testsDir.deletingLastPathComponent().deletingLastPathComponent()

/// One recorded step of a scenario, for Core's reducer tests: what the test
/// asked for (`command`) or what the registry reported (`event`).
struct FixtureStep: Codable {
    var t: Double // seconds since the scenario began
    var command: String? // "setFrame", "minimize", "deminimize"
    var event: String? // "frameChanged", "minimized", "focused", "appeared", "closed", "title"
    var frame: CGRect?
    var value: Bool?
}

struct Fixture: Codable {
    var scenario: String
    var note: String
    var screens: [ScreenInfo]
    var window: WindowID
    var initialFrame: CGRect
    var steps: [FixtureStep]
}

@MainActor
final class Session {
    let process = Process()
    let pid: Int32
    let registry: WindowRegistry
    private(set) var steps: [FixtureStep] = []
    private var origin = Date()
    private var watched: WindowID?

    init(_ frames: [CGRect]) throws {
        try #require(Permissions.accessibility(), "grant Accessibility to the terminal running the tests")
        process.executableURL = packageDir.appendingPathComponent(".build/debug/mielwm-testwindows")
        process.arguments = ["--frames", frames.map { "\($0.minX),\($0.minY),\($0.width),\($0.height)" }.joined(separator: ";")]
        let out = Pipe()
        process.standardOutput = out
        try process.run() // fails with "run swift build first" style errors if the helper is missing
        let line = String(decoding: out.fileHandleForReading.availableData, as: UTF8.self)
        pid = try #require(Int32(line.trimmingCharacters(in: .whitespacesAndNewlines)))
        var record: (SystemEvent) -> Void = { _ in }
        registry = WindowRegistry(pidFilter: pid) { record($0) }
        record = { [unowned self] in self.record($0) }
    }

    /// Starts the registry and returns the helper's windows, PT-1 first.
    func start(count: Int) async throws -> [WindowSnapshot] {
        registry.start()
        try #require(await until { self.registry.windows.count == count })
        return registry.windows.values.sorted { $0.title < $1.title }
    }

    func end() {
        registry.stop()
        process.terminate()
        process.waitUntilExit()
    }

    /// Starts a scenario: steps are recorded for `window` from now on.
    func begin(_ window: WindowID) {
        watched = window
        steps = []
        origin = Date()
    }

    func perform(_ commands: [WindowCommand]) {
        log(commands)
        registry.perform(commands)
    }

    func performAndWait(_ commands: [WindowCommand]) -> Bool {
        log(commands)
        return registry.performAndWait(commands)
    }

    func setMinimized(_ id: WindowID, _ minimized: Bool) {
        steps.append(FixtureStep(t: now(), command: minimized ? "minimize" : "deminimize"))
        axWindow(id)?.set(kAXMinimizedAttribute, minimized as CFBoolean)
    }

    /// The helper's window as an AX element, for actions the registry does not offer.
    func axWindow(_ id: WindowID) -> AXUIElement? {
        let windows = AXUIElementCreateApplication(pid).value(kAXWindowsAttribute) as? [AXUIElement] ?? []
        return windows.first { $0.windowNumber == id.number }
    }

    func frame(_ id: WindowID) -> CGRect? { registry.windows[id]?.frame }

    func until(_ timeout: Double = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    /// Lets trailing notifications arrive.
    func settle(_ seconds: Double = 0.4) async {
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }

    func reportedFrames() -> [CGRect] { steps.filter { $0.event == "frameChanged" }.compactMap(\.frame) }

    func writeFixture(_ scenario: String, note: String, initial: CGRect) throws {
        let fixture = Fixture(scenario: scenario, note: note, screens: Displays.screens(), window: watched!,
                              initialFrame: initial, steps: steps)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let dir = testsDir.appendingPathComponent("Fixtures")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try encoder.encode(fixture).write(to: dir.appendingPathComponent("\(scenario).json"))
    }

    private func now() -> Double { (Date().timeIntervalSince(origin) * 1000).rounded() / 1000 }

    private func log(_ commands: [WindowCommand]) {
        for case .setFrame(let id, let frame) in commands where id == watched {
            steps.append(FixtureStep(t: now(), command: "setFrame", frame: frame))
        }
    }

    private func record(_ event: SystemEvent) {
        let step: FixtureStep? = switch event {
        case .windowFrameChanged(watched, let frame): FixtureStep(t: now(), event: "frameChanged", frame: frame)
        case .windowMinimized(watched, let value): FixtureStep(t: now(), event: "minimized", value: value)
        case .windowFocused(watched): FixtureStep(t: now(), event: "focused")
        case .windowTitleChanged(watched, _): FixtureStep(t: now(), event: "title")
        case .windowClosed(watched): FixtureStep(t: now(), event: "closed")
        case .windowAppeared(let s) where s.id == watched: FixtureStep(t: now(), event: "appeared", frame: s.frame)
        default: nil
        }
        if let step { steps.append(step) }
    }
}

@Suite(.serialized, .enabled(if: enabled, "set MIELWM_SYSTEM_TESTS=1 to open test windows"))
@MainActor
struct WindowTests {
    @Test func enumeratesHelperWindows() async throws {
        let frames = [CGRect(x: 160, y: 160, width: 420, height: 300), CGRect(x: 640, y: 220, width: 360, height: 260)]
        let s = try Session(frames)
        defer { s.end() }
        let windows = try await s.start(count: 2)
        #expect(windows.map(\.title) == ["PT-1", "PT-2"])
        for (window, frame) in zip(windows, frames) {
            #expect(window.frame == frame)
            #expect(window.isStandard && window.isResizable && window.isMovable && !window.isMinimized)
            #expect(window.appName == "mielwm-testwindows" && window.id.pid == s.pid)
        }
    }

    @Test func setFrameLandsAndIsReported() async throws {
        let start = CGRect(x: 200, y: 180, width: 420, height: 300)
        let s = try Session([start])
        defer { s.end() }
        let id = try #require(try await s.start(count: 1).first).id
        s.begin(id)
        let target = CGRect(x: 360, y: 240, width: 520, height: 360)
        #expect(s.performAndWait([.setFrame(id, target)]))
        #expect(await s.until { s.frame(id) == target })
        await s.settle()
        #expect(s.reportedFrames().last == target)
        try s.writeFixture("set-frame", note: "One setFrame (size, position, size) on a visible window.", initial: start)
    }

    @Test func eventsArriveInOrder() async throws {
        let start = CGRect(x: 220, y: 200, width: 400, height: 280)
        let s = try Session([start])
        defer { s.end() }
        let id = try #require(try await s.start(count: 1).first).id
        s.begin(id)
        let a = CGRect(x: 260, y: 220, width: 400, height: 280), b = CGRect(x: 420, y: 300, width: 460, height: 300)
        s.perform([.setFrame(id, a)])
        #expect(await s.until { s.frame(id) == a })
        s.setMinimized(id, true)
        #expect(await s.until { s.registry.windows[id]?.isMinimized == true })
        s.setMinimized(id, false)
        #expect(await s.until { s.registry.windows[id]?.isMinimized == false })
        s.perform([.setFrame(id, b)])
        #expect(await s.until { s.frame(id) == b })
        await s.settle()

        let events = s.steps.filter { $0.event != nil }
        let firstA = events.firstIndex { $0.frame == a }, lastB = events.lastIndex { $0.frame == b }
        let minimized = events.firstIndex { $0.event == "minimized" && $0.value == true }
        let restored = events.firstIndex { $0.event == "minimized" && $0.value == false }
        #expect(firstA != nil && minimized != nil && restored != nil && lastB != nil)
        if let firstA, let minimized, let restored, let lastB {
            #expect(firstA < minimized && minimized < restored && restored < lastB)
        }
        #expect(s.reportedFrames().last == b)
        try s.writeFixture("minimize", note: "setFrame, minimize, deminimize, setFrame; minimize driven over AX by the test.",
                           initial: start)
    }

    @Test func smallStepsLikeADrag() async throws {
        let start = CGRect(x: 200, y: 200, width: 400, height: 280)
        let s = try Session([start])
        defer { s.end() }
        let id = try #require(try await s.start(count: 1).first).id
        s.begin(id)
        var frame = start
        for _ in 0..<12 {
            frame.origin.x += 20
            frame.origin.y += 8
            s.perform([.setFrame(id, frame)])
            try await Task.sleep(for: .milliseconds(16))
        }
        let last = frame
        #expect(await s.until { s.frame(id) == last })
        await s.settle()
        #expect(s.reportedFrames().last == last)
        try s.writeFixture("drag-steps", note: "12 setFrame moves 16 ms apart, same size, like a drag at 60 Hz.",
                           initial: start)
    }

    @Test func parksInACornerAndComesBack() async throws {
        let start = CGRect(x: 300, y: 200, width: 480, height: 320)
        let s = try Session([start])
        defer { s.end() }
        let id = try #require(try await s.start(count: 1).first).id
        let screen = try #require(Displays.screens().first { $0.frame.intersects(start) })
        s.begin(id)
        let parked = parkFrame(start, on: screen)
        #expect(s.performAndWait([.setFrame(id, parked)]))
        await s.settle(0.5)
        let landed = try #require(s.frame(id))
        let visible = landed.intersection(screen.frame)
        #expect(visible.width * visible.height < 0.05 * landed.width * landed.height, "landed at \(landed)")
        #expect(s.performAndWait([.setFrame(id, start)]))
        #expect(await s.until { s.frame(id) == start })
        await s.settle()
        try s.writeFixture("park", note: "Park in the bottom-right corner with 1 pt showing, then back. Asked \(parked), landed \(landed).",
                           initial: start)
    }

    @Test func clampedAboveTheTopEdge() async throws {
        let start = CGRect(x: 300, y: 240, width: 480, height: 320)
        let s = try Session([start])
        defer { s.end() }
        let id = try #require(try await s.start(count: 1).first).id
        let desk = Displays.screens().map(\.frame).reduce(CGRect.null) { $0.union($1) }
        s.begin(id)
        let above = CGRect(x: start.minX, y: desk.minY - start.height - 100, width: start.width, height: start.height)
        #expect(s.performAndWait([.setFrame(id, above)]))
        await s.settle(0.5)
        let landed = try #require(s.frame(id))
        #expect(landed != above && landed.minY >= desk.minY, "landed at \(landed)")
        #expect(s.performAndWait([.setFrame(id, start)]))
        #expect(await s.until { s.frame(id) == start })
        await s.settle()
        try s.writeFixture("clamp-top", note: "setFrame fully above every display; macOS pulls it back. Asked \(above), landed \(landed).",
                           initial: start)
    }

    @Test func closeIsReported() async throws {
        let s = try Session([CGRect(x: 320, y: 260, width: 400, height: 280)])
        defer { s.end() }
        let id = try #require(try await s.start(count: 1).first).id
        s.begin(id)
        let button = s.axWindow(id)?.value(kAXCloseButtonAttribute)
        AXUIElementPerformAction(try #require(button as! AXUIElement?), kAXPressAction as CFString)
        #expect(await s.until { s.registry.windows[id] == nil })
        #expect(s.steps.map(\.event) == ["closed"])
    }

    @Test func stillOfAParkedWindow() async throws {
        let start = CGRect(x: 300, y: 220, width: 480, height: 320)
        let s = try Session([start])
        defer { s.end() }
        let id = try #require(try await s.start(count: 1).first).id
        let screen = try #require(Displays.screens().first { $0.frame.intersects(start) })
        #expect(s.performAndWait([.setFrame(id, parkFrame(start, on: screen))]))
        await s.settle()

        let capture = CaptureManager()
        let began = Date()
        await withCheckedContinuation { done in capture.captureStills([id]) { done.resume() } }
        let elapsed = Date().timeIntervalSince(began)
        guard case .image(let image)? = capture.latestFrame(for: id) else {
            Issue.record("no still of the parked window")
            return
        }
        #expect(image.width == Int(start.width * screen.scale) && image.height == Int(start.height * screen.scale))
        #expect(capture.generation(for: id) == 1)
        print("still of a parked window: \(image.width)x\(image.height) in \(Int(elapsed * 1000)) ms")
        #expect(s.performAndWait([.setFrame(id, start)]))
    }

    /// The overview parks a window with the picture it has and takes a fresh still while it moves.
    @Test func stillsTakenWhileParkingAreComplete() async throws {
        let start = CGRect(x: 320, y: 240, width: 480, height: 320)
        let s = try Session([start])
        defer { s.end() }
        let id = try #require(try await s.start(count: 1).first).id
        let screen = try #require(Displays.screens().first { $0.frame.intersects(start) })
        let capture = CaptureManager()
        func still() async throws -> [Bool] {
            await withCheckedContinuation { done in capture.captureStills([id]) { done.resume() } }
            guard case .image(let image)? = capture.latestFrame(for: id) else { throw CancellationError() }
            #expect(image.width == Int(start.width * screen.scale) && image.height == Int(start.height * screen.scale))
            return try opaqueGrid(image)
        }
        let before = try await still()
        s.perform([.setFrame(id, parkFrame(start, on: screen))])
        let moving = try await still()
        await s.settle()
        let parked = try await still()
        #expect(before.filter { $0 }.count > before.count / 2)
        #expect(moving == before && parked == before)
        #expect(s.performAndWait([.setFrame(id, start)]))
    }

    @Test func streamOfAVisibleWindow() async throws {
        let start = CGRect(x: 260, y: 200, width: 600, height: 400)
        let s = try Session([start])
        defer { s.end() }
        let id = try #require(try await s.start(count: 1).first).id
        let capture = CaptureManager()
        var firstFrame: WindowID?
        capture.onFirstFrame = { firstFrame = $0 }
        capture.setRate(.overview)
        capture.warm([id], maxPixelSize: CGSize(width: 800, height: 800))
        #expect(await s.until { firstFrame == id })

        let fast0 = capture.generation(for: id)
        try await Task.sleep(for: .seconds(1))
        let fast = capture.generation(for: id) - fast0
        capture.setRate(.idle)
        try await Task.sleep(for: .milliseconds(600))
        let idle0 = capture.generation(for: id)
        try await Task.sleep(for: .seconds(2))
        let idle = Double(capture.generation(for: id) - idle0) / 2
        if case .pixelBuffer(let pixels)? = capture.latestFrame(for: id) {
            #expect(CVPixelBufferGetWidth(pixels) == 800 && CVPixelBufferGetHeight(pixels) <= 800)
        } else {
            Issue.record("no live frame")
        }
        capture.stop()
        print("stream of a visible window: \(fast) fps at the overview rate, \(idle) fps idle")
        #expect(fast >= 30) // the helper repaints at 60 Hz
        #expect(idle <= 3)
    }

    @Test func listenOnlyTapStartsAndStops() {
        let tap = EventTap { _ in }
        #expect(tap.start(listenOnly: true))
        tap.stop()
    }

    @Test func wallpaperImages() async throws {
        let screen = try #require(Displays.screens().first)
        let window = await withCheckedContinuation { done in Wallpaper.captureWallpaperWindow(screen) { done.resume(returning: $0) } }
        #expect(window != nil)
        let picture = await withCheckedContinuation { done in Wallpaper.image(for: screen) { done.resume(returning: $0) } }
        #expect(picture != nil)
    }
}

/// The bottom-right corner of `screen` with 1 pt showing, as AeroSpace parks.
private func parkFrame(_ frame: CGRect, on screen: ScreenInfo) -> CGRect {
    CGRect(x: screen.frame.maxX - 1, y: screen.frame.maxY - 1, width: frame.width, height: frame.height)
}

/// Whether each point of a 16x16 grid over `image` is opaque: a picture with parts missing differs.
private func opaqueGrid(_ image: CGImage) throws -> [Bool] {
    let width = image.width, height = image.height
    let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let pixels = try #require(ctx.data).assumingMemoryBound(to: UInt8.self)
    return (0 ..< 256).map { i in
        let x = (i % 16 * 2 + 1) * width / 32, y = (i / 16 * 2 + 1) * height / 32
        return pixels[(y * width + x) * 4 + 3] > 250
    }
}
