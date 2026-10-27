enum Mode: Equatable {
    case normal
    /// Tests: no event tap, no overlays, no menu, never takes focus; manages
    /// only this pid's windows and is driven over the socket.
    case manageOnly(Int32)

    var pid: Int32? { if case let .manageOnly(pid) = self { pid } else { nil } }
}
