import Foundation

public enum GatewayAdmissionError: Error, Equatable, Sendable {
    case duplicateEventID
    case invalidated
    case invalidRetainedBodyBytes
    case overloaded
    case timedOut
    case notAcceptingRequests
}

package protocol ProviderRequestPooling: Sendable {
    func admit(_ admission: ProviderRequestAdmission) async throws
    func finish(eventID: UUID) async
    func shutdown() async
    func reconfigure(_ configuration: ProviderRequestPoolConfiguration) async
    func snapshot() async -> ProviderRequestPoolSnapshot
}

package struct ProviderRequestRouteKey: Hashable, Sendable {
    package var client: GatewayClient
    package var modelIdentifier: String

    package init(client: GatewayClient, modelIdentifier: String) {
        self.client = client
        self.modelIdentifier = modelIdentifier
    }

    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.client.providerRequestPoolDiscriminator == rhs.client.providerRequestPoolDiscriminator
            && lhs.modelIdentifier == rhs.modelIdentifier
    }

    package func hash(into hasher: inout Hasher) {
        hasher.combine(client.providerRequestPoolDiscriminator)
        hasher.combine(modelIdentifier)
    }
}

package struct ProviderRequestRouteTarget: Equatable, Sendable {
    package var providerID: UUID
    package var modelID: String

    package init(providerID: UUID, modelID: String) {
        self.providerID = providerID
        self.modelID = modelID
    }
}

package struct ProviderRequestPoolProviderConfiguration: Equatable, Sendable {
    package var id: UUID
    package var displayName: String
    package var maximumParallelRequests: Int
    package var revision: UInt64

    package init(
        id: UUID,
        displayName: String,
        maximumParallelRequests: Int,
        revision: UInt64
    ) {
        self.id = id
        self.displayName = displayName
        self.maximumParallelRequests = maximumParallelRequests
        self.revision = revision
    }
}

package struct ProviderRequestPoolConfiguration: Equatable, Sendable {
    package var providers: [ProviderRequestPoolProviderConfiguration]
    package var routes: [ProviderRequestRouteKey: ProviderRequestRouteTarget]

    package init(
        providers: [ProviderRequestPoolProviderConfiguration],
        routes: [ProviderRequestRouteKey: ProviderRequestRouteTarget]
    ) {
        self.providers = providers
        self.routes = routes
    }
}

package struct ProviderRequestAdmission: Equatable, Sendable {
    package var eventID: UUID
    package var providerID: UUID
    package var providerRevision: UInt64
    package var client: GatewayClient
    package var modelIdentifier: String
    package var targetModelID: String
    package var retainedBodyBytes: Int

    package init(
        eventID: UUID,
        providerID: UUID,
        providerRevision: UInt64,
        client: GatewayClient,
        modelIdentifier: String,
        targetModelID: String,
        retainedBodyBytes: Int
    ) {
        self.eventID = eventID
        self.providerID = providerID
        self.providerRevision = providerRevision
        self.client = client
        self.modelIdentifier = modelIdentifier
        self.targetModelID = targetModelID
        self.retainedBodyBytes = retainedBodyBytes
    }

    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.eventID == rhs.eventID
            && lhs.providerID == rhs.providerID
            && lhs.providerRevision == rhs.providerRevision
            && lhs.client.providerRequestPoolDiscriminator
                == rhs.client.providerRequestPoolDiscriminator
            && lhs.modelIdentifier == rhs.modelIdentifier
            && lhs.targetModelID == rhs.targetModelID
            && lhs.retainedBodyBytes == rhs.retainedBodyBytes
    }
}

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

public struct ProviderRequestPoolSnapshot: Equatable, Sendable {
    public var totalRunning: Int
    public var totalWaiting: Int
    public var providers: [ProviderRequestPoolProviderSnapshot]

    public init(
        totalRunning: Int,
        totalWaiting: Int,
        providers: [ProviderRequestPoolProviderSnapshot]
    ) {
        self.totalRunning = totalRunning
        self.totalWaiting = totalWaiting
        self.providers = providers
    }
}

package struct ProviderRequestPoolQueueStorageSnapshot: Equatable, Sendable {
    package var storedEventIDCount: Int
    package var consumedPrefixCount: Int
    package var liveWaiterCount: Int

    package init(
        storedEventIDCount: Int,
        consumedPrefixCount: Int,
        liveWaiterCount: Int
    ) {
        self.storedEventIDCount = storedEventIDCount
        self.consumedPrefixCount = consumedPrefixCount
        self.liveWaiterCount = liveWaiterCount
    }
}

extension GatewayClient {
    fileprivate var providerRequestPoolDiscriminator: UInt8 {
        switch self {
        case .claude:
            0
        case .codex:
            1
        }
    }
}
