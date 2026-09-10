struct StatusItemVisibilitySnapshot: Equatable, Sendable {
    let statusItemVisible: Bool
    let windowVisible: Bool
    let occlusionVisible: Bool

    var isPresented: Bool {
        statusItemVisible && windowVisible && occlusionVisible
    }
}

struct StatusItemVisibilityRecoveryPolicy: Sendable {
    private var attemptedForCurrentHiddenEpisode = false

    mutating func shouldRecreate(for snapshot: StatusItemVisibilitySnapshot) -> Bool {
        if snapshot.isPresented {
            attemptedForCurrentHiddenEpisode = false
            return false
        }
        guard !attemptedForCurrentHiddenEpisode else {
            return false
        }
        attemptedForCurrentHiddenEpisode = true
        return true
    }
}
