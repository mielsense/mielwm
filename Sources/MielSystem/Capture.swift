import CoreMedia
import Foundation
import MielCore
import ScreenCaptureKit
import VideoToolbox

/// Window images for Render. Live SCStreams for windows that are on screen
/// (start them just before the overview opens), stills for parked windows:
/// SCStream delivers nothing for windows off screen.
///
/// SCK's async overloads resolve to the wrong symbols under the Command Line
/// Tools, so every call here uses the completion-handler form.
public final class CaptureManager: NSObject, WindowFrameSource, @unchecked Sendable {
    public enum Rate: Sendable {
        case overview // 60 fps
        case linger // 15 fps: the overlay just closed and may open again
        case idle // 2 fps
    }

    /// Main queue, once per `warm`: the first fresh frame of that window.
    public var onFirstFrame: ((WindowID) -> Void)?
    private var wake: (() -> Void)? // see `wakeOnNextPicture`

    private struct Slot {
        var frame: WindowFrame?
        var generation: UInt64 = 0
        var live: (stream: SCStream, config: SCStreamConfiguration)?
        var waitingForFirstFrame = false
        var sameFrames = 0 // live frames in a row that matched the stored picture
        var quiet = false // its stream runs at `quietInterval` until the picture changes

        mutating func store(_ frame: WindowFrame) {
            self.frame = frame
            generation &+= 1
        }
    }

    private let lock = NSLock()
    private var slots: [WindowID: Slot] = [:]
    private var scWindows: [UInt32: SCWindow] = [:]
    private var rate = Rate.idle
    private var closed: Set<WindowID> = [] // a still that lands after its window closed is dropped
    private var stops = 0 // bumps when every stream stops, so a warm still looking windows up gives up
    private let sampleQueue = DispatchQueue(label: "mielwm.capture", qos: .userInteractive)

    override public init() {}

    // MARK: WindowFrameSource

    public func latestFrame(for id: WindowID) -> WindowFrame? {
        lock.withLock { slots[id]?.frame }
    }

    public func generation(for id: WindowID) -> UInt64 {
        lock.withLock { slots[id]?.generation ?? 0 }
    }

    /// `body` runs once on the main queue, when the next new picture of any window is stored.
    public func wakeOnNextPicture(_ body: @escaping () -> Void) {
        lock.withLock { wake = body }
    }

    // MARK: Streams

    /// Starts a stream for each window that has none, scaled to fit
    /// `maxPixelSize`, at the current rate.
    /// shortcut: a stream keeps the size it started with, so a window resized
    /// meanwhile is scaled to fit; stop and warm it again if that shows.
    public func warm(_ ids: [WindowID], maxPixelSize: CGSize) {
        let (missing, stops) = lock.withLock {
            closed.subtract(ids) // asked for again: it is back
            return (ids.filter { slots[$0]?.live == nil }, self.stops)
        }
        guard !missing.isEmpty else { return }
        withWindows(missing) { windows in
            for (id, window) in windows { self.startStream(id, window, maxPixelSize, stops: stops) }
        }
    }

    public func setRate(_ rate: Rate) {
        let streams: [(stream: SCStream, config: SCStreamConfiguration)] = lock.withLock {
            guard self.rate != rate else { return [] }
            self.rate = rate
            return slots.keys.compactMap { id in
                slots[id]!.sameFrames = 0
                slots[id]!.quiet = false
                slots[id]!.live?.config.minimumFrameInterval = Self.interval(rate)
                return slots[id]!.live
            }
        }
        for (stream, config) in streams { stream.updateConfiguration(config) { _ in } }
    }

    /// Stops the streams of `ids` (all when nil). The last image stays
    /// unless `dropFrames`, which also forgets the window (it closed).
    public func stop(_ ids: [WindowID]? = nil, dropFrames: Bool = false) {
        let streams: [SCStream] = lock.withLock {
            if ids == nil { stops += 1 }
            return (ids ?? Array(slots.keys)).compactMap { id in
                let stream = slots[id]?.live?.stream
                if dropFrames { slots[id] = nil; closed.insert(id) } else { slots[id]?.live = nil }
                return stream
            }
        }
        for stream in streams { stream.stopCapture { _ in } }
    }

    /// Stops every stream and turns each last live frame into a still at
    /// `scale` of its size, letting go of SCK's full-size buffers.
    public func cool(stillScale scale: CGFloat) {
        stop()
        let frames: [(WindowID, UInt64, CVPixelBuffer)] = lock.withLock {
            slots.compactMap { id, slot in
                if case let .pixelBuffer(buffer)? = slot.frame { (id, slot.generation, buffer) } else { nil }
            }
        }
        guard !frames.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            for (id, generation, buffer) in frames {
                let still = Self.still(of: buffer, scale: scale)
                self.lock.withLock {
                    // A newer picture or a new stream wins.
                    guard self.slots[id]?.generation == generation, self.slots[id]?.live == nil else { return }
                    if let still { self.slots[id]!.store(.image(still)) } else { self.slots[id]!.frame = nil }
                }
            }
        }
    }

    /// Halves the stills of `ids` (windows long out of sight) to hold less
    /// memory; the next warm takes fresh ones before they come into view.
    public func shrinkStills(_ ids: [WindowID]) {
        let stills: [(WindowID, UInt64, CGImage)] = lock.withLock {
            ids.compactMap { id in
                guard let slot = slots[id], slot.live == nil, case let .image(image)? = slot.frame, image.width >= 256 else { return nil }
                return (id, slot.generation, image)
            }
        }
        guard !stills.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            for (id, generation, image) in stills {
                guard let small = Self.scaled(image, by: 0.5) else { continue }
                self.lock.withLock {
                    guard self.slots[id]?.generation == generation else { return } // a newer picture wins
                    self.slots[id]!.store(.image(small))
                }
            }
        }
    }

    /// A copy of `buffer` at `scale` of its size, in its own color space.
    static func still(of buffer: CVPixelBuffer, scale: CGFloat) -> CGImage? {
        var made: CGImage?
        VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &made)
        return made.flatMap { scaled($0, by: scale) }
    }

    /// `image` at `scale` of its size, 8-bit BGRA premultiplied in its own color space.
    static func scaled(_ image: CGImage, by scale: CGFloat) -> CGImage? {
        let width = max(1, Int((CGFloat(image.width) * scale).rounded())), height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    // MARK: Stills

    /// Stills of `ids` at `scale` of their full pixel size (take them at the
    /// size they are drawn: a full 2x still costs ~220 ms), in parallel.
    /// `completion` runs on the main queue after the last one.
    public func captureStills(_ ids: [WindowID], scale: CGFloat = 1, completion: (() -> Void)? = nil) {
        lock.withLock { closed.subtract(ids) } // asked for again: it is back
        withWindows(ids) { windows in
            let group = DispatchGroup()
            for (id, window) in windows {
                group.enter()
                let filter = SCContentFilter(desktopIndependentWindow: window)
                SCScreenshotManager.captureImage(contentFilter: filter,
                                                 configuration: Self.configuration(filter, maxPixelSize: nil, scale: scale)) { image, _ in
                    if let image { self.store(.image(image), for: id) }
                    group.leave()
                }
            }
            group.notify(queue: .main) { completion?() }
        }
    }

    /// Re-reads which windows SCK can capture. Runs by itself when an id is unknown.
    func refreshContent(_ completion: (() -> Void)? = nil) {
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { content, _ in
            if let content {
                let windows = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
                self.lock.withLock { self.scWindows = windows }
            }
            completion?()
        }
    }

    // MARK: Private

    func store(_ frame: WindowFrame, for id: WindowID) {
        var woken: (() -> Void)?
        lock.withLock {
            guard !closed.contains(id) else { return }
            slots[id, default: Slot()].store(frame)
            swap(&woken, &wake)
        }
        woken.map { DispatchQueue.main.async(execute: $0) }
    }

    private func withWindows(_ ids: [WindowID], _ body: @escaping ([(WindowID, SCWindow)]) -> Void) {
        let lookup = { self.lock.withLock { ids.compactMap { id in self.scWindows[id.number].map { (id, $0) } } } }
        let found = lookup()
        if found.count == ids.count { return body(found) }
        refreshContent { body(lookup()) }
    }

    private func startStream(_ id: WindowID, _ window: SCWindow, _ maxPixelSize: CGSize, stops: Int) {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = Self.configuration(filter, maxPixelSize: maxPixelSize)
        config.queueDepth = 4
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        let started: Bool = lock.withLock {
            guard slots[id]?.live == nil, self.stops == stops else { return false } // cooled meanwhile
            config.minimumFrameInterval = Self.interval(rate)
            slots[id, default: Slot()].live = (stream, config)
            slots[id]!.waitingForFirstFrame = true
            return true
        }
        guard started else { return }
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        } catch {
            return forget(stream)
        }
        stream.startCapture { error in
            if error != nil { self.forget(stream) }
        }
    }

    private func forget(_ stream: SCStream) {
        lock.withLock {
            for (id, slot) in slots where slot.live?.stream === stream { slots[id]?.live = nil }
        }
    }

    private static func configuration(_ filter: SCContentFilter, maxPixelSize: CGSize?, scale fraction: CGFloat = 1) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        let pixels = CGSize(width: filter.contentRect.width * scale, height: filter.contentRect.height * scale)
        let fit = min(maxPixelSize.map { min(1, $0.width / pixels.width, $0.height / pixels.height) } ?? 1, max(fraction, 0.05))
        config.width = max(1, Int(pixels.width * fit))
        config.height = max(1, Int(pixels.height * fit))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true // Render draws its own
        return config
    }

    private static func interval(_ rate: Rate) -> CMTime {
        switch rate {
        case .overview: CMTime(value: 1, timescale: 60)
        case .linger: CMTime(value: 1, timescale: 15)
        case .idle: CMTime(value: 1, timescale: 2)
        }
    }

    /// A stream whose picture has not changed for `quietAfter` frames slows to this until it does.
    private static let quietInterval = interval(.linger)
    private static let quietAfter = 30

    /// Every `rowStride`th row of two BGRA buffers, from row `phase`, holds the same bytes.
    /// shortcut: a change under `rowStride` rows tall can take up to `rowStride` frames to
    /// show (each frame reads other rows); read every row if that ever shows.
    static func sameRows(_ a: CVPixelBuffer, _ b: CVPixelBuffer, phase: Int) -> Bool {
        let width = CVPixelBufferGetWidth(a), height = CVPixelBufferGetHeight(a), bytesPerRow = CVPixelBufferGetBytesPerRow(a)
        guard CVPixelBufferGetWidth(b) == width, CVPixelBufferGetHeight(b) == height, CVPixelBufferGetBytesPerRow(b) == bytesPerRow,
              CVPixelBufferGetPixelFormatType(a) == kCVPixelFormatType_32BGRA, CVPixelBufferGetPixelFormatType(b) == kCVPixelFormatType_32BGRA
        else { return false }
        CVPixelBufferLockBaseAddress(a, .readOnly)
        CVPixelBufferLockBaseAddress(b, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(a, .readOnly)
            CVPixelBufferUnlockBaseAddress(b, .readOnly)
        }
        guard let pa = CVPixelBufferGetBaseAddress(a), let pb = CVPixelBufferGetBaseAddress(b) else { return false }
        for row in stride(from: phase % rowStride, to: height, by: rowStride)
            where memcmp(pa + row * bytesPerRow, pb + row * bytesPerRow, width * 4) != 0 { return false }
        return true
    }

    static let rowStride = 8
}

extension CaptureManager: SCStreamOutput, SCStreamDelegate {
    public func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Idle and blank samples carry no image; only complete frames count.
        guard type == .screen, let pixels = buffer.imageBuffer,
              let info = (CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
              let status = info[.status] as? Int, status == SCFrameStatus.complete.rawValue
        else { return }
        // A frame that says nothing changed would only make Render draw the same picture again.
        let unchanged = (info[.dirtyRects] as? [Any])?.isEmpty ?? false
        guard let (id, stored, checks): (WindowID, CVPixelBuffer?, Int) = lock.withLock({
            guard let id = slots.first(where: { $0.value.live?.stream === stream })?.key else { return nil }
            if slots[id]!.waitingForFirstFrame { return (id, nil, 0) }
            if unchanged { return nil }
            guard case let .pixelBuffer(stored)? = slots[id]!.frame else { return (id, nil, 0) }
            return (id, stored, slots[id]!.sameFrames)
        }) else { return }
        // Each time the display recomposes, SCK sends the window again with all of it marked
        // dirty (macOS 27): compare the pixels. Outside the lock, which the main thread reads under.
        let same = stored.map { Self.sameRows(pixels, $0, phase: checks) } ?? false
        var slow: (stream: SCStream, config: SCStreamConfiguration)?
        var woken: (() -> Void)?
        let first: WindowID? = lock.withLock {
            guard var slot = slots[id], slot.live?.stream === stream else { return nil }
            defer { slots[id] = slot }
            // Quiet until two frames in a row change: a lone change (a title bar's shade flickering) is only drawn.
            let changedBefore = slot.sameFrames == 0
            slot.sameFrames = same ? slot.sameFrames + 1 : 0
            let quiet = same ? slot.quiet || slot.sameFrames >= Self.quietAfter : slot.quiet && !changedBefore
            if quiet != slot.quiet, let live = slot.live, rate == .overview {
                slot.quiet = quiet
                live.config.minimumFrameInterval = quiet ? Self.quietInterval : Self.interval(rate)
                slow = live
            }
            if same { return nil }
            slot.store(.pixelBuffer(pixels))
            swap(&woken, &wake)
            guard slot.waitingForFirstFrame else { return nil }
            slot.waitingForFirstFrame = false
            return id
        }
        slow.map { $0.stream.updateConfiguration($0.config) { _ in } }
        woken.map { DispatchQueue.main.async(execute: $0) }
        if let first { DispatchQueue.main.async { self.onFirstFrame?(first) } }
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        forget(stream)
    }
}
