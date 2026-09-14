package enum AppliedCodexState: Sendable {
    case disconnected
    case connected(AppliedCodexSnapshot)
}
