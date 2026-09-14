import Foundation
import LittleSwitchCommon

/// The same process-owned source is passed to every HTTP/TLS listener generation.
public struct GatewayMonitoring: Sendable {
    public let store: MonitoringStore
    package let configuration: @Sendable () async -> MonitoringConfiguration
    package let recordLog: @Sendable (MonitoringLogEntry) async -> Void

    public init(
        store: MonitoringStore,
        configuration: @escaping @Sendable () async -> MonitoringConfiguration = { .init() },
        recordLog: @escaping @Sendable (MonitoringLogEntry) async -> Void = { _ in }
    ) {
        self.store = store
        self.configuration = configuration
        self.recordLog = recordLog
    }

    package func begin(requestID: UUID, route: MonitoringRoute) async -> MonitoringRequestContext {
        let client: MonitoringClient =
            switch route {
            case .messages, .countTokens: .claude
            case .responses: .codex
            case .models, .unknown: .unknown
            }
        let context = MonitoringRequestContext(monitoring: self, requestID: requestID, client: client, route: route)
        await store.beginRequest(client: client, route: route)
        return context
    }

    package func recordOperation(_ operation: MonitoringOperation) async {
        let entry = await store.recordOperation(operation)
        await recordLog(entry)
    }
}

package enum GatewayMonitoringScope {
    @TaskLocal package static var current: MonitoringRequestContext?
}
