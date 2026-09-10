import Foundation
import LittleSwitchCore

struct TrafficLogSnapshot: Equatable, Sendable {
    var events: [TrafficEvent]
    var persistenceError: String?

    init(events: [TrafficEvent], persistenceError: String? = nil) {
        self.events = events
        self.persistenceError = persistenceError
    }
}

public struct TrafficLogClock: Sendable {
    var now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date) {
        self.now = now
    }

    public static let system = TrafficLogClock(now: Date.init)
}

public struct TrafficLogIOHooks: Sendable {
    var beforeCreateSegment: @Sendable (URL) throws -> Void
    var beforeWrite: @Sendable (URL, Data) throws -> Void
    package var beforeUpdateModificationDate: @Sendable (URL) throws -> Void
    var beforeRemoveSegment: @Sendable (URL) throws -> Void

    public init(
        beforeCreateSegment: @escaping @Sendable (URL) throws -> Void = { _ in },
        beforeWrite: @escaping @Sendable (URL, Data) throws -> Void = { _, _ in },
        beforeRemoveSegment: @escaping @Sendable (URL) throws -> Void = { _ in }
    ) {
        self.beforeCreateSegment = beforeCreateSegment
        self.beforeWrite = beforeWrite
        beforeUpdateModificationDate = { _ in }
        self.beforeRemoveSegment = beforeRemoveSegment
    }

    package init(
        beforeUpdateModificationDate: @escaping @Sendable (URL) throws -> Void
    ) {
        self.init()
        self.beforeUpdateModificationDate = beforeUpdateModificationDate
    }

    public static let none = TrafficLogIOHooks()
}

public struct TrafficOperationalSummary: Equatable, Sendable {
    var eventID: UUID
    var method: String
    var path: String
    var claudeRoute: String?
    var providerName: String?
    var modelID: String?
    var lifecycle: TrafficLifecycle
    var status: Int?
    var requestBytes: Int
    var responseBytes: Int
    var duration: TimeInterval?

    public init(event: TrafficEvent) {
        eventID = event.id
        method = event.method
        path = event.path
        claudeRoute = event.claudeRoute
        providerName = event.providerName
        modelID = event.modelID
        lifecycle = event.lifecycle
        status = event.finalStatus
        requestBytes = event.requestBytes
        responseBytes = event.responseBytes
        duration = event.duration
    }
}

public enum TrafficStoreOperationalState: Equatable, Sendable {
    case persistenceFailed(String)
    case persistenceRecovered
    case corruptRecordIgnored(String)
}

protocol TrafficOperationalLogging: Sendable {
    func requestFinished(_ summary: TrafficOperationalSummary)
    func storeStateChanged(_ state: TrafficStoreOperationalState)
}

public struct NoopTrafficOperationalLogger: TrafficOperationalLogging {
    public init() {}

    public func requestFinished(_ summary: TrafficOperationalSummary) {
        _ = summary
    }

    public func storeStateChanged(_ state: TrafficStoreOperationalState) {
        _ = state
    }
}

extension TrafficAction {
    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            true
        default:
            false
        }
    }
}
