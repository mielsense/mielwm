// Pure parts of System. These always run and never open windows, post
// events or install taps.

import Carbon.HIToolbox
import CoreVideo
import Foundation
import os
import ImageIO
import MielCore
@testable import MielIPC
@testable import MielSystem
import Testing

/// A new folder for one test, inside this run's own, which goes when the run ends.
func scratchDir(_ name: String) throws -> URL {
    let url = scratchRoot.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private let scratchRoot: URL = {
    atexit { try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("mielwm-system-tests-\(getpid())")) }
    return FileManager.default.temporaryDirectory.appendingPathComponent("mielwm-system-tests-\(getpid())", isDirectory: true)
}()

// MARK: - Chords

@Test func chordsTakeTheKeyCodeTheConfigNames() throws {
    func chord(_ text: String) throws -> Chord? { Chord(try #require(KeyChord(text))) }
    #expect(try chord("ctrl+opt+g") == Chord(UInt16(kVK_ANSI_G), [.control, .option]))
    #expect(try chord("opt+shift+left") == Chord(UInt16(kVK_LeftArrow), [.option, .shift]))
    #expect(try chord("Cmd+,") == Chord(UInt16(kVK_ANSI_Comma), .command))
    #expect(try chord("alt+-") == Chord(UInt16(kVK_ANSI_Minus), .option))
    #expect(try chord("alt+=") == Chord(UInt16(kVK_ANSI_Equal), .option))
    #expect(try chord("cmd+f1") == Chord(UInt16(kVK_F1), .command))
    #expect(try chord("tab") == Chord(UInt16(kVK_Tab)))
    #expect(KeyChord.allKeys.allSatisfy { Chord.keyCode($0) != nil }, "every key the config can name")
}

// MARK: - Tap routing

private func key(_ code: Int, _ modifiers: Modifiers = [], down: Bool = true, isRepeat: Bool = false) -> TapInput {
    .key(down: down, KeyPress(keyCode: UInt16(code), modifiers: modifiers, isRepeat: isRepeat))
}

private func tapState() -> TapState {
    var state = TapState()
    state.table = BindingTable(bindings: [
        Chord(KeyChord("ctrl+opt+g")!)!: .toggleOverview,
        Chord(KeyChord("opt+shift+left")!)!: .nudge(.left),
        Chord(KeyChord("opt+tab")!)!: .switchWindow(forward: true),
        Chord(KeyChord("opt+shift+tab")!)!: .switchWindow(forward: false),
    ])
    return state
}

@Test func boundChordIsConsumedTogetherWithItsKeyUp() {
    var router = TapRouter()
    let state = tapState()
    #expect(router.route(key(kVK_ANSI_G, [.control, .option]), state)
        == TapOutput(consume: true, events: [.action(.toggleOverview, isRepeat: false)]))
    // The modifiers are often released first; the key-up is still ours.
    #expect(router.route(key(kVK_ANSI_G, down: false), state).consume)
    #expect(!router.route(key(kVK_ANSI_G, down: false), state).consume)
}

@Test func unboundKeysPassWithExactModifiers() {
    var router = TapRouter()
    let state = tapState()
    #expect(router.route(key(kVK_ANSI_G), state) == TapOutput())
    #expect(router.route(key(kVK_ANSI_G, [.control, .option, .shift]), state) == TapOutput())
    #expect(router.route(key(kVK_ANSI_G, down: false), state) == TapOutput())
}

@Test func optionNoOpChordsAreSwallowed() {
    var router = TapRouter()
    let state = tapState()
    for chord in ["opt+1", "opt+0", "opt+shift+5", "opt+/", "opt+,", "opt+;"] {
        let c = Chord(KeyChord(chord)!)!
        #expect(router.route(key(Int(c.keyCode), c.modifiers), state)
            == TapOutput(consume: true), "\(chord)")
    }
    #expect(router.route(key(kVK_ANSI_A, .option), state) == TapOutput())
}

@Test func heldKeysRepeatOnlyRepeatingActions() {
    var router = TapRouter()
    let state = tapState()
    #expect(router.route(key(kVK_ANSI_G, [.control, .option], isRepeat: true), state) == TapOutput(consume: true))
    #expect(router.route(key(kVK_LeftArrow, [.option, .shift], isRepeat: true), state)
        == TapOutput(consume: true, events: [.action(.nudge(.left), isRepeat: true)]))
}

@Test func keyCaptureForwardsUnboundKeysOnly() {
    var router = TapRouter()
    var state = tapState()
    state.keyCapture = true
    let press = KeyPress(keyCode: UInt16(kVK_ANSI_F), modifiers: [], characters: "f")
    #expect(router.route(.key(down: true, press), state) == TapOutput(consume: true, events: [.key(press)]))
    #expect(router.route(key(kVK_ANSI_F, down: false), state).consume)
    #expect(router.route(key(kVK_ANSI_G, [.control, .option]), state).events == [.action(.toggleOverview, isRepeat: false)])
}

@Test func switcherReleaseIsReportedBeforeTheMainThreadKnows() {
    var router = TapRouter()
    let state = tapState() // `switcher` still false: main has not seen the action yet
    _ = router.route(key(kVK_Tab, [.option, .shift]), state)
    #expect(router.route(.flags(.option), state).events == [.modifiers(.option)])
    #expect(router.route(.flags([]), state).events == [.modifiers([])])
    #expect(router.route(.flags(.option), state).events == [])
}

@Test func switcherTakesEscape() {
    var router = TapRouter()
    var state = tapState()
    #expect(router.route(key(kVK_Escape, .option), state) == TapOutput())
    state.switcher = true
    let esc = KeyPress(keyCode: UInt16(kVK_Escape), modifiers: .option)
    #expect(router.route(.key(down: true, esc), state) == TapOutput(consume: true, events: [.key(esc)]))
    #expect(router.route(.flags(.option), state).events == [.modifiers(.option)])
}

@Test func middleClickWithoutDragIsReplayed() {
    var router = TapRouter()
    let state = tapState()
    let start = CGPoint(x: 100, y: 100)
    #expect(router.route(.mouse(.down, button: 2, at: start, modifiers: []), state) == TapOutput(consume: true))
    #expect(router.route(.mouse(.dragged, button: 2, at: CGPoint(x: 106, y: 106), modifiers: []), state)
        == TapOutput(consume: true))
    #expect(router.route(.mouse(.up, button: 2, at: CGPoint(x: 106, y: 106), modifiers: []), state)
        == TapOutput(consume: true, replayMiddleClick: true))
}

@Test func middleDragPastThresholdPans() {
    var router = TapRouter()
    let state = tapState()
    let start = CGPoint(x: 100, y: 100)
    _ = router.route(.mouse(.down, button: 2, at: start, modifiers: []), state)
    #expect(router.route(.mouse(.dragged, button: 2, at: CGPoint(x: 112, y: 100), modifiers: []), state)
        == TapOutput(consume: true, events: [.pan(.began, start), .pan(.changed, CGPoint(x: 112, y: 100))]))
    #expect(router.route(.mouse(.dragged, button: 2, at: CGPoint(x: 140, y: 90), modifiers: []), state).events
        == [.pan(.changed, CGPoint(x: 140, y: 90))])
    #expect(router.route(.mouse(.up, button: 2, at: CGPoint(x: 140, y: 90), modifiers: []), state)
        == TapOutput(consume: true, events: [.pan(.ended, CGPoint(x: 140, y: 90))]))
}

@Test func modifierDragsMoveAndResize() {
    var router = TapRouter()
    let state = tapState()
    let p = CGPoint(x: 10, y: 20), q = CGPoint(x: 30, y: 40)
    #expect(router.route(.mouse(.down, button: 0, at: p, modifiers: [.control, .option]), state)
        == TapOutput(consume: true, events: [.move(.began, p)]))
    // Releasing the modifiers mid-drag keeps the gesture.
    #expect(router.route(.mouse(.dragged, button: 0, at: q, modifiers: []), state).events == [.move(.changed, q)])
    #expect(router.route(.mouse(.up, button: 0, at: q, modifiers: []), state).events == [.move(.ended, q)])
    #expect(router.route(.mouse(.down, button: 1, at: p, modifiers: [.control, .option]), state).events
        == [.resize(.began, p)])
    #expect(router.route(.mouse(.up, button: 1, at: q, modifiers: [.control, .option]), state).events
        == [.resize(.ended, q)])
}

@Test func plainClicksAndOtherButtonsPass() {
    var router = TapRouter()
    let state = tapState()
    let p = CGPoint(x: 1, y: 1)
    #expect(router.route(.mouse(.down, button: 0, at: p, modifiers: []), state) == TapOutput())
    #expect(router.route(.mouse(.dragged, button: 0, at: p, modifiers: []), state) == TapOutput())
    #expect(router.route(.mouse(.down, button: 1, at: p, modifiers: .control), state) == TapOutput())
    #expect(router.route(.mouse(.down, button: 3, at: p, modifiers: [.control, .option]), state) == TapOutput())
}

@Test func controlOptionWheelZoomsAndPinchNeedsTheOverview() {
    var router = TapRouter()
    var state = tapState()
    let p = CGPoint(x: 5, y: 5)
    #expect(router.route(.scroll(lines: 1.5, at: p, modifiers: [.control, .option]), state)
        == TapOutput(consume: true, events: [.zoom(lines: 1.5, at: p)]))
    #expect(router.route(.scroll(lines: 1.5, at: p, modifiers: .control), state) == TapOutput()) // Accessibility Zoom's
    #expect(router.route(.scroll(lines: 1.5, at: p, modifiers: []), state) == TapOutput())
    #expect(router.route(.magnify(0.1, at: p), state) == TapOutput())
    state.overviewOpen = true
    #expect(router.route(.magnify(0.1, at: p), state) == TapOutput(consume: true, events: [.magnify(0.1, at: p)]))
}

@Test func resetEndsGesturesInProgress() {
    var router = TapRouter()
    let state = tapState()
    _ = router.route(.mouse(.down, button: 2, at: .zero, modifiers: []), state)
    _ = router.route(.mouse(.dragged, button: 2, at: CGPoint(x: 50, y: 0), modifiers: []), state)
    #expect(router.reset() == [.pan(.ended, CGPoint(x: 50, y: 0))])
    #expect(router.route(.mouse(.up, button: 2, at: .zero, modifiers: []), state) == TapOutput())
}

@Test func pointerEventsAreWantedOnlyWhileTheyCanMatter() {
    var router = TapRouter()
    var state = tapState()
    #expect(!router.wantsPointer(state)) // plain clicks, drags and scrolls never visit us
    _ = router.route(.flags(.option), state)
    #expect(!router.wantsPointer(state))
    _ = router.route(.flags(.control), state) // ⌃ alone is no longer a pointer modifier (Accessibility Zoom has it)
    #expect(!router.wantsPointer(state))
    _ = router.route(.flags([.control, .option]), state) // the move and zoom modifiers
    #expect(router.wantsPointer(state))
    _ = router.route(.mouse(.down, button: 0, at: .zero, modifiers: [.control, .option]), state)
    _ = router.route(.flags([]), state)
    #expect(router.wantsPointer(state)) // the drag goes on after the modifiers are let go
    _ = router.route(.mouse(.up, button: 0, at: .zero, modifiers: []), state)
    #expect(!router.wantsPointer(state))
    state.overviewOpen = true // pinches and the wheel in the overview
    #expect(router.wantsPointer(state))
    state.overviewOpen = false
    _ = router.route(.flags([.control, .option, .shift]), state)
    #expect(!router.wantsPointer(state))
    _ = router.route(.flags([.control, .option]), state)
    _ = router.route(.mouse(.down, button: 1, at: .zero, modifiers: [.control, .option]), state)
    _ = router.reset() // the system switched the tap off mid-drag
    #expect(!router.wantsPointer(state))
    _ = router.reset(held: [.control, .option]) // switched off while ⌃⌥ stays down
    #expect(router.wantsPointer(state))
}

// MARK: - File watching

@Test func fileWatcherSeesEveryKindOfEdit() throws {
    let root = try scratchDir("watch") // watched while `dir` is missing; others' temporary files never land in it
    let dir = root.appendingPathComponent("mielwm"), file = dir.appendingPathComponent("config.json")
    let calls = DispatchSemaphore(value: 0), queue = DispatchQueue(label: "test.watch")
    let watcher = FileWatcher([file, dir.appendingPathComponent("other.json")], queue: queue) { calls.signal() }
    defer { watcher.stop() }
    func expectCall(_ what: String) {
        #expect(calls.wait(timeout: .now() + 10) == .success, "\(what)")
        while calls.wait(timeout: .now() + 0.5) == .success {} // one edit may report twice
    }
    queue.sync {} // the watcher has armed on the root
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: file) // the directory and the file appear
    expectCall("created")
    let handle = try FileHandle(forWritingTo: file) // written in place
    handle.seekToEndOfFile()
    handle.write(Data(" ".utf8))
    try handle.close()
    expectCall("written in place")
    try Data("{\"a\": 1}".utf8).write(to: file, options: .atomic) // a temporary file renamed over it
    expectCall("replaced")
    try FileManager.default.removeItem(at: file)
    expectCall("deleted")
    #expect(calls.wait(timeout: .now() + 0.5) == .timedOut) // quiet while nothing changes
}

// MARK: - Captures

@Test func aLiveFrameBecomesASmallStill() throws {
    var made: CVPixelBuffer?
    CVPixelBufferCreate(nil, 400, 200, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &made)
    let buffer = try #require(made)
    CVPixelBufferLockBaseAddress(buffer, [])
    let base = try #require(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
    for i in stride(from: 0, to: CVPixelBufferGetBytesPerRow(buffer) * 200, by: 4) { (base + i).update(from: [200, 100, 50, 255], count: 4) } // BGRA
    CVPixelBufferUnlockBaseAddress(buffer, [])
    let still = try #require(CaptureManager.still(of: buffer, scale: 0.5))
    #expect(still.width == 200 && still.height == 100)
    let bytes = try #require(CFDataGetBytePtr(still.dataProvider?.data))
    #expect(abs(Int(bytes[0]) - 200) <= 2 && abs(Int(bytes[1]) - 100) <= 2 && abs(Int(bytes[2]) - 50) <= 2 && bytes[3] == 255)
}

/// The overview pauses once its displays found nothing new; a picture stored after they
/// looked but before the pause asked to be woken must still wake it.
@Test(.timeLimit(.minutes(1))) func aPictureStoredBeforeTheWakeIsAskedForWakesAtOnce() async throws {
    let capture = CaptureManager()
    let id = WindowID(pid: 1, number: 7)
    let ctx = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue))
    let image = try #require(ctx.makeImage())
    let looked = capture.picturesStored
    capture.store(.image(image), for: id) // between the last look and the pause
    await withCheckedContinuation { done in capture.wakeOnNextPicture(after: looked) { done.resume() } }

    let woke = OSAllocatedUnfairLock(initialState: false)
    let waiting = capture.picturesStored
    await withCheckedContinuation { done in
        capture.wakeOnNextPicture(after: waiting) { woke.withLock { $0 = true }; done.resume() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            #expect(!woke.withLock { $0 }) // nothing new yet
            capture.store(.image(image), for: id)
        }
    }
    #expect(woke.withLock { $0 })
}

@Test func framesWithTheSamePixelsAreTheSamePicture() throws {
    func buffer(_ width: Int = 64, _ height: Int = 48) throws -> CVPixelBuffer {
        var made: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &made)
        let b = try #require(made)
        CVPixelBufferLockBaseAddress(b, [])
        memset(CVPixelBufferGetBaseAddress(b), 0x40, CVPixelBufferGetBytesPerRow(b) * height)
        CVPixelBufferUnlockBaseAddress(b, [])
        return b
    }
    let a = try buffer(), b = try buffer()
    #expect(CaptureManager.sameRows(a, b, phase: 0))
    CVPixelBufferLockBaseAddress(b, [])
    (CVPixelBufferGetBaseAddress(b)! + 13 * CVPixelBufferGetBytesPerRow(b) + 4 * 63).storeBytes(of: 0x41, as: UInt8.self) // one pixel of row 13
    CVPixelBufferUnlockBaseAddress(b, [])
    // Each frame reads other rows: one of `rowStride` frames in a row sees it.
    let phases = (0..<CaptureManager.rowStride).filter { !CaptureManager.sameRows(a, b, phase: $0) }
    #expect(phases == [13 % CaptureManager.rowStride])
    #expect(!CaptureManager.sameRows(a, try buffer(64, 40), phase: 0)) // another size
}

@Test func stillsScaleToHalf() throws {
    let context = try #require(CGContext(data: nil, width: 800, height: 400, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
    let image = try #require(context.makeImage())
    let half = try #require(CaptureManager.scaled(image, by: 0.5))
    #expect(half.width == 400 && half.height == 200)
}

// GitHub's macOS runners never run the utility-QoS shrink within 30 s, though
// default-QoS work runs fine; stillsScaleToHalf checks the scaling there.
@Test(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "utility QoS stalls on CI runners"))
func stillsOfWindowsLongOutOfSightShrink() throws {
    func image(_ width: Int) throws -> CGImage {
        try #require(CGContext(data: nil, width: width, height: width / 2, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)?.makeImage())
    }
    let capture = CaptureManager()
    let big = WindowID(pid: 1, number: 1), small = WindowID(pid: 1, number: 2)
    capture.store(.image(try image(800)), for: big)
    capture.store(.image(try image(200)), for: small) // already small: kept
    capture.shrinkStills([big, small, WindowID(pid: 1, number: 3)])
    let deadline = Date().addingTimeInterval(30) // utility work waits long on a busy CI runner
    while capture.generation(for: big) == 1, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
    guard case let .image(shrunk)? = capture.latestFrame(for: big), case let .image(kept)? = capture.latestFrame(for: small) else {
        Issue.record("stills missing")
        return
    }
    #expect(shrunk.width == 400 && shrunk.height == 200)
    #expect(kept.width == 200 && capture.generation(for: small) == 1)
}

// MARK: - Wallpaper

@Test func wallpaperIsDecodedJustLargeEnoughToCoverTheScreen() throws {
    let url = try scratchDir("wallpaper").appendingPathComponent("wallpaper.png")
    let ctx = try #require(CGContext(data: nil, width: 4000, height: 2000, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(dest, try #require(ctx.makeImage()), nil)
    #expect(CGImageDestinationFinalize(dest))
    let covering = try #require(Wallpaper.decode(url, covering: CGSize(width: 1000, height: 1000)))
    #expect(covering.width == 2000 && covering.height == 1000) // as tall as the screen, wider
    let full = try #require(Wallpaper.decode(url, covering: CGSize(width: 6000, height: 3000)))
    #expect(full.width == 4000 && full.height == 2000) // never scaled up
}

// MARK: - Displays

@Test func appKitRectsConvertToYDown() {
    let primaryHeight: CGFloat = 1169
    #expect(Displays.toYDown(CGRect(x: 0, y: 0, width: 1800, height: 1169), primaryHeight: primaryHeight)
        == CGRect(x: 0, y: 0, width: 1800, height: 1169))
    // A 1080p display standing above the laptop.
    #expect(Displays.toYDown(CGRect(x: -79, y: 1169, width: 1920, height: 1080), primaryHeight: primaryHeight)
        == CGRect(x: -79, y: -1080, width: 1920, height: 1080))
    // The visible frame under a 37 pt menu bar.
    #expect(Displays.toYDown(CGRect(x: 0, y: 0, width: 1800, height: 1132), primaryHeight: primaryHeight)
        == CGRect(x: 0, y: 37, width: 1800, height: 1132))
}

@Test func primaryScreenSitsAtTheOrigin() {
    let screens = Displays.screens()
    #expect(screens.first?.frame.origin == .zero)
    #expect(screens.allSatisfy { $0.frame.contains($0.visibleFrame) && $0.scale >= 1 })
}

// MARK: - IPC

private func socketPath(_ name: String) -> String { "/tmp/mielwm-\(getpid())-\(name).sock" }

@Test @MainActor func ipcRoundTrip() async throws {
    let path = socketPath("rt")
    let server = try IPCServer(path: path) { args, reply in
        reply(try! JSONEncoder().encode(["echo": args]))
    }
    defer { server.stop() }
    // The server replies on the main queue, which other tests keep busy on slow CI runners.
    let response = try await Task.detached { try IPCClient.send(["focus", "left"], path: path, timeout: 30) }.value
    #expect(try JSONDecoder().decode([String: [String]].self, from: response) == ["echo": ["focus", "left"]])
    #expect(throws: IPCError.alreadyRunning) { try IPCServer(path: path) { _, _ in } }
}

@Test @MainActor func ipcRejectsMalformedRequests() async throws {
    let path = socketPath("bad")
    let server = try IPCServer(path: path) { _, reply in reply(Data("{}".utf8)) }
    defer { server.stop() }
    let response = try await Task.detached { () throws -> Data? in
        let fd = try connectSocket(path)
        defer { close(fd) }
        writeLine(fd, Data(#"{"not":"an array"}"#.utf8))
        return readLine(fd)
    }.value
    #expect(response == Data(#"{"error":"bad request"}"#.utf8))
}

@Test func ipcReplacesAStaleSocketAndReportsNoServer() throws {
    let path = socketPath("stale")
    FileManager.default.createFile(atPath: path, contents: Data())
    let server = try IPCServer(path: path) { _, _ in }
    server.stop()
    #expect(!FileManager.default.fileExists(atPath: path))
    #expect(throws: IPCError.notRunning) { try IPCClient.send(["state"], path: path) }
}

/// Runs the built `aerospace` command against `path` and returns what it printed.
private func aerospace(_ args: [String], socket path: String) async throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".build/debug/mielwm-aerospace")
    process.arguments = args
    process.environment = ["MIELWM_SOCKET": path]
    let out = Pipe()
    process.standardOutput = out
    try process.run()
    return try await Task.detached {
        let data = try out.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }.value
}

// The command speaks the socket protocol without Foundation, so check it against the real server.
@Test(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "the command waits 0.3 s, and CI runners keep the main queue busy"))
@MainActor func aerospaceCommandTalksToTheServer() async throws {
    let path = socketPath("aero")
    let odd = "quote \" backslash \\ tab \t newline \n é 🙂"
    let server = try IPCServer(path: path) { args, reply in
        switch args.dropFirst().first {
        case "echo": reply(try! JSONEncoder().encode(Array(args.dropFirst(2))))
        case "list-nothing": reply(Data(#"{"error":"unknown command"}"#.utf8))
        default: reply(Data())
        }
    }
    #expect(try await aerospace(["echo", odd, ""], socket: path) == #"["quote \" backslash \\ tab \t newline \n é 🙂",""]"# + "\n")
    #expect(try await aerospace(["focus", "left"], socket: path) == "") // an action prints nothing
    #expect(try await aerospace(["list-nothing"], socket: path) == "[]\n") // a command mielwm doesn't know
    server.stop()
    #expect(try await aerospace(["list-workspaces", "--all"], socket: path) == "[]\n") // no mielwm
    #expect(try await aerospace(["workspace", "2"], socket: path) == "")
}

@Test func threeFingersSidewaysMakeOneStepPerSwipe() {
    var r = SwipeRecognizer()
    func fingers(_ x: Double, _ y: Double = 0.5) -> [CGPoint] { [-0.1, 0, 0.1].map { CGPoint(x: x + $0, y: y) } }
    #expect(r.feed(fingers(0.6)) == nil) // landed
    #expect(r.feed(fingers(0.55)) == nil) // not far enough yet
    #expect(r.feed(fingers(0.45)) == true) // fingers moved left: the next workspace
    #expect(r.feed(fingers(0.2)) == nil) // one step per swipe
    #expect(r.feed([]) == nil) // lifted
    #expect(r.feed(fingers(0.3)) == nil)
    #expect(r.feed(fingers(0.45)) == false) // to the right: the previous one
    _ = r.feed([])
    #expect(r.feed(fingers(0.5, 0.2)) == nil)
    #expect(r.feed(fingers(0.62, 0.5)) == nil) // mostly vertical: not a swipe
    _ = r.feed([])
    _ = r.feed(Array(fingers(0.5)) + [CGPoint(x: 0.9, y: 0.9)]) // four fingers: Mission Control's
    #expect(r.feed(Array(fingers(0.2)) + [CGPoint(x: 0.9, y: 0.9)]) == nil)
}

// MARK: - Screens

@Test func screensReportedOnWakeKeepTheCacheCurrent() {
    var seen: [[ScreenInfo]] = []
    let registry = WindowRegistry { if case .screensChanged(let s) = $0 { seen.append(s) } }
    func screen(_ id: UInt32, _ width: CGFloat) -> [ScreenInfo] {
        let frame = CGRect(x: 0, y: 0, width: width, height: 900)
        return [ScreenInfo(id: id, name: "S\(id)", frame: frame, visibleFrame: frame, scale: 2)]
    }
    let a = screen(1, 1440), b = screen(2, 1920)
    registry.report(a)
    registry.report(b, always: true) // waking, with an external display gone
    registry.report(b, always: true) // the second wake notification
    registry.report(a) // the display is back
    registry.report(a)
    #expect(seen == [a, b, b, a])
}

// The root of WindowRegistry.stop() crashing before start(): stopping its observer thread before it ran.
@Test func aThreadThatNeverStartedStopsQuietly() {
    RunLoopThread(name: "mielwm.test").stop()
}

// MARK: - Window registry

/// The app reads the screens for Core before the registry starts: a change in between still arrives.
@MainActor @Test func screensThatChangedBeforeTheRegistryStartedAreReported() {
    var events: [SystemEvent] = []
    let registry = WindowRegistry(pidFilter: -1) { events.append($0) } // no such app: nothing is tracked
    let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
    let gone = ScreenInfo(id: 9999, name: "Gone", frame: frame, visibleFrame: frame, scale: 1)
    registry.start(screens: [gone])
    defer { registry.stop() }
    #expect(events.contains { if case let .screensChanged(now) = $0 { !now.contains(gone) } else { false } })
}
