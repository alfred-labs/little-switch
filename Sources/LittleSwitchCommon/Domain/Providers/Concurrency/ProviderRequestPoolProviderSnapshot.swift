import Foundation

public struct ProviderRequestPoolProviderSnapshot: Equatable, Sendable {
    public var id: UUID
    // Captured identity and limit remain part of the diagnostic snapshot,
    // including providers draining across removal and reconfiguration.
    // periphery:ignore
    public var displayName: String
    // periphery:ignore
    public var maximumParallelRequests: Int
    public var runningCount: Int
    public var waitingCount: Int
    // Queue bounds and age are inspected by cancellation, timeout and state
    // machine checks even though Overview only displays the global counts.
    // periphery:ignore
    public var retainedWaitingBytes: Int
    // periphery:ignore
    public var oldestWaitDuration: Duration?
    public var isRemoved: Bool

    public init(
        id: UUID,
        displayName: String,
        maximumParallelRequests: Int,
        runningCount: Int,
        waitingCount: Int,
        retainedWaitingBytes: Int,
        oldestWaitDuration: Duration?,
        isRemoved: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.maximumParallelRequests = maximumParallelRequests
        self.runningCount = runningCount
        self.waitingCount = waitingCount
        self.retainedWaitingBytes = retainedWaitingBytes
        self.oldestWaitDuration = oldestWaitDuration
        self.isRemoved = isRemoved
    }
}
