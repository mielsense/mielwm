import Foundation

/// Calls `onChange` shortly after any of `files` (all in one directory) is
/// written, created, replaced, renamed or deleted, by anything. Kernel
/// vnode events: no polling, no wakeups while nothing changes. Calls can
/// come for changes that leave the files as they were; compare before acting.
public final class FileWatcher {
    private let files: [URL]
    private let queue: DispatchQueue
    private let onChange: () -> Void
    private var sources: [DispatchSourceFileSystemObject] = [] // on `queue`
    private var pending: DispatchWorkItem?
    private var stopped = false

    public init(_ files: [URL], queue: DispatchQueue = .main, onChange: @escaping () -> Void) {
        self.files = files
        self.queue = queue
        self.onChange = onChange
        queue.async { self.arm() }
    }

    public func stop() {
        queue.async {
            self.stopped = true
            self.pending?.cancel()
            self.sources.forEach { $0.cancel() }
            self.sources = []
        }
    }

    deinit { sources.forEach { $0.cancel() } }

    /// The files that exist, and their directory (or, while it does not
    /// exist, the nearest one above it that does) for files appearing.
    private func arm() {
        sources.forEach { $0.cancel() }
        sources = []
        guard !stopped, let first = files.first else { return }
        var dir = first.deletingLastPathComponent()
        while !watch(dir, [.write, .delete, .rename]), dir.pathComponents.count > 1 { dir.deleteLastPathComponent() }
        for file in files { watch(file, [.write, .extend, .attrib, .delete, .rename]) }
    }

    @discardableResult
    private func watch(_ url: URL, _ mask: DispatchSource.FileSystemEvent) -> Bool {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return false }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: queue)
        source.setEventHandler { [weak self] in self?.changed() }
        source.setCancelHandler { close(fd) }
        source.resume()
        sources.append(source)
        return true
    }

    /// Editors write a temporary file and rename it over, apps truncate and
    /// write: wait until the burst is over, then look again from scratch.
    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped else { return }
            self.arm()
            self.onChange()
        }
        pending = work
        queue.asyncAfter(deadline: .now() + 0.1, execute: work)
    }
}
