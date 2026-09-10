import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring safe observations")
struct MonitoringObservationTests {
    @Test("Only bounded resolved model metadata survives a terminal observation")
    func boundedModel() throws {
        let observation = MonitoringObservation(
            requestID: UUID(),
            finishedAt: Date(),
            durationSeconds: -.infinity,
            client: .unknown,
            route: .unknown,
            outcome: .clientError,
            resolvedModel: String(repeating: "猫", count: 100),
            statusCode: 99,
            estimatedInputTokens: -5,
            webSearchCount: -1,
            errorKind: .invalidRequest)
        #expect(observation.resolvedModel == String(repeating: "猫", count: 85))
        #expect(observation.truncated)
        #expect(observation.statusCode == nil)
        #expect(observation.durationSeconds == 0)
        #expect(observation.estimatedInputTokens == 0)
        #expect(observation.webSearchCount == 0)
        let entry = MonitoringLogEntry(observation: observation)
        #expect(entry.level == .warn)
        #expect(entry.message == "Gateway request rejected.")
        #expect(entry.truncated)
        #expect(try JSONEncoder().encode(entry).count <= 4_096)
    }

    @Test("Every terminal category has controlled event text and severity")
    func terminalLevels() {
        let expected: [(MonitoringOutcome, (MonitoringLevel, String))] = [
            (.success, (.info, "gateway.request.completed")),
            (.clientError, (.warn, "gateway.request.failed")),
            (.serverError, (.error, "gateway.request.failed")),
            (.transportError, (.error, "gateway.request.failed")),
            (.cancelled, (.warn, "gateway.request.cancelled")),
        ]
        for (outcome, (level, event)) in expected {
            let observation = MonitoringObservation(
                requestID: UUID(),
                finishedAt: Date(),
                durationSeconds: 1,
                client: .claude,
                route: .messages,
                outcome: outcome)
            let entry = MonitoringLogEntry(observation: observation)
            #expect(entry.level == level)
            #expect(entry.eventName == event)
            #expect(!entry.truncated)
        }
    }
}
