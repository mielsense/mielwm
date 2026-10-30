import CoreGraphics
import Foundation

// Undo and redo. Before each change, Core saves every window's frame and the
// workspaces, so the change can be put back.

/// What undo puts back.
struct UndoEntry: Sendable {
    var frames: [WindowID: CGRect]
    var workspaces: [Workspace]
}

/// The last change saved, so a held key's repeats count as one step.
struct Checkpoint: Hashable, Sendable {
    var kind: String
    var window: WindowID?
    var time: Double
}

extension CanvasState {
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
