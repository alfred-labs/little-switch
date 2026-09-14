import Foundation
import LittleSwitchCommon
import LittleSwitchSearch
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring process metrics")
struct MonitoringMetricsTests {
    @Test("Request completion balances its gauge and preserves missing provider usage")
    func terminalObservation() async {
        let resource = MonitoringResource(
            serviceVersion: "test", instanceID: UUID(), startedAt: Date(timeIntervalSince1970: 1))
        let store = MonitoringStore(resource: resource)
        #expect(await store.snapshot().families.isEmpty)
        await store.beginRequest(client: .claude, route: .messages)
        _ = await store.finish(
            MonitoringObservation(
                requestID: UUID(),
                finishedAt: Date(timeIntervalSince1970: 2),
                durationSeconds: 0.3,
                client: .claude,
                route: .messages,
                outcome: .success,
                statusCode: 200,
                estimatedInputTokens: 9))
        let snapshot = await store.snapshot()
        #expect(snapshot.resource == resource)
        #expect(snapshot.family(.requests)?.points.map(\.value) == [.counter(1)])
        #expect(snapshot.family(.inFlight)?.points.map(\.value) == [.gauge(0)])
        #expect(snapshot.family(.tokens) == nil)
        #expect(snapshot.family(.estimatedInputTokens)?.points.map(\.value) == [.counter(9)])
        var expectedHistogram = MonitoringHistogram()
        expectedHistogram.record(0.3)
        #expect(snapshot.family(.duration)?.points.map(\.value) == [.histogram(expectedHistogram.snapshot)])
    }

    @Test("A family includes its single overflow series in the 2048 series budget")
    func boundedSeries() async {
        let store = MonitoringStore()
        for _ in 0..<2_049 {
            _ = await store.finish(
                MonitoringObservation(
                    requestID: UUID(),
                    finishedAt: Date(),
                    durationSeconds: 1,
                    client: .codex,
                    route: .responses,
                    outcome: .success,
                    providerID: UUID(),
                    statusCode: 200))
        }
        let requests = await store.snapshot().family(.requests)
        #expect(requests?.points.count == 2_048)
        #expect(requests?.points.first { $0.attributes == [.overflow] }?.value == .counter(2))
    }

    @Test("Queue provider churn preserves the process series cap and clears retired gauges")
    func providerChurn() async {
        let store = MonitoringStore()
        let firstProvider = UUID()
        let initial = await store.snapshot(providerPool: pool(providerIDs: [firstProvider]))
        #expect(initial.family(.waiting)?.points.map(\.value) == [.gauge(1)])
        let providers = (0..<2_049).map { _ in UUID() }
        let crowded = await store.snapshot(providerPool: pool(providerIDs: providers))
        #expect(crowded.family(.waiting)?.points.count == 2_048)
        #expect(
            crowded.family(.waiting)?.points.first { $0.attributes == [.providerID(firstProvider)] }?.value
                == .gauge(0))
        #expect(crowded.family(.waiting)?.points.first { $0.attributes == [.overflow] }?.value == .gauge(3))
        let cleared = await store.snapshot(providerPool: pool(providerIDs: []))
        #expect(cleared.family(.waiting)?.points.count == 2_048)
        #expect(cleared.family(.waiting)?.points.allSatisfy { $0.value == .gauge(0) } == true)
        #expect(await store.snapshot().resource == initial.resource)
    }

    @Test("Signed OTLP counts saturate without conflating estimates or admission categories")
    func signedCountsAndBusinessEvents() async {
        let store = MonitoringStore()
        for outcome in MonitoringAdmissionOutcome.allCases { await store.recordAdmission(outcome) }
        for reason in MonitoringDropReason.allCases {
            await store.recordDrop(signal: .logs, reason: reason, count: .max)
            await store.recordDrop(signal: .logs, reason: reason)
        }
        for provider in WebSearchProvider.allCases {
            for outcome in MonitoringWebSearchOutcome.allCases {
                await store.recordWebSearch(provider: provider, outcome: outcome)
            }
        }
        for _ in 0..<2 {
            await store.beginRequest(client: .codex, route: .responses)
            await store.finish(
                MonitoringObservation(
                    requestID: UUID(),
                    finishedAt: Date(),
                    durationSeconds: 1,
                    client: .codex,
                    route: .responses,
                    outcome: .success,
                    usage: GatewayUsageTotals(
                        inputTokens: .max, outputTokens: 2, cacheReadTokens: 3, cacheWriteTokens: 4),
                    estimatedInputTokens: .max))
        }
        let snapshot = await store.snapshot()
        #expect(snapshot.family(.admissionTimeouts)?.points.map(\.value) == [.counter(1)])
        #expect(snapshot.family(.admissionRejections)?.points.count == 4)
        #expect(snapshot.family(.dropped)?.points.allSatisfy { $0.value == .counter(UInt64(Int64.max)) } == true)
        #expect(snapshot.family(.webSearches)?.points.count == 15)
        for outcome in MonitoringWebSearchOutcome.allCases {
            #expect(
                snapshot.family(.webSearches)?.points.first {
                    $0.attributes == [.searchProvider(.exa), .searchOutcome(outcome)]
                }?.value == .counter(1)
            )
        }
        let values = snapshot.family(.tokens)?.points
        #expect(
            values?.first { $0.attributes.contains(.tokenType(.input)) }?.value == .counter(UInt64(Int64.max)))
        #expect(values?.first { $0.attributes.contains(.tokenType(.output)) }?.value == .counter(4))
        #expect(values?.first { $0.attributes.contains(.tokenType(.cacheRead)) }?.value == .counter(6))
        #expect(values?.first { $0.attributes.contains(.tokenType(.cacheWrite)) }?.value == .counter(8))
        #expect(snapshot.family(.estimatedInputTokens)?.points.map(\.value) == [.counter(UInt64(Int64.max))])
        #expect(snapshot.family(.inFlight)?.points.map(\.value) == [.gauge(0)])
    }

    @Test("Synthetic and operational observations never count as AI requests")
    func operationCounters() async throws {
        let store = MonitoringStore()
        let started = await store.recordOperation(.gatewayStarted)
        let marker = await store.markTest()
        let stopped = await store.recordOperation(.gatewayStopped)
        let snapshot = await store.snapshot()
        #expect(snapshot.families.map(\.name) == [.test])
        #expect(snapshot.family(.test)?.points.map(\.value) == [.gauge(1)])
        #expect(try await store.logs().entries == [started, marker, stopped])
    }

    private func pool(providerIDs: [UUID]) -> ProviderRequestPoolSnapshot {
        ProviderRequestPoolSnapshot(
            totalRunning: 0,
            totalWaiting: providerIDs.count,
            providers: providerIDs.map {
                ProviderRequestPoolProviderSnapshot(
                    id: $0,
                    displayName: "not a metric label",
                    maximumParallelRequests: 1,
                    runningCount: 0,
                    waitingCount: 1,
                    retainedWaitingBytes: 0,
                    oldestWaitDuration: nil,
                    isRemoved: false
                )
            })
    }
}
