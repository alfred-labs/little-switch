import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring request lifecycle boundaries")
struct MonitoringRequestContextBoundaryTests {
    @Test("The exchange bound rejects new identities but still updates an already retained exchange")
    func exchangeBound() async throws {
        let store = MonitoringStore()
        let context = await GatewayMonitoring(store: store).begin(requestID: UUID(), route: .messages)
        let identifiers = (0..<128).map { _ in UUID() }
        for identifier in identifiers { await context.usage(exchangeID: identifier, totals: .init(inputTokens: 1)) }
        let first = try #require(identifiers.first)
        await context.usage(
            exchangeID: first, totals: .init(inputTokens: 4, outputTokens: 3, cacheReadTokens: 2, cacheWriteTokens: 1))
        await context.usage(exchangeID: UUID(), totals: .init(inputTokens: 99))
        await context.usage(exchangeID: UUID(), totals: .init(inputTokens: 99))
        await context.invalidUsage(count: -1)
        await context.invalidUsage(count: 0)
        await context.invalidUsage(count: 2)
        await context.invalidUsage(count: 3)
        await context.finish(statusCode: 200)
        #expect(
            try await store.logs().entries.first?.attributes.usage
                == .init(inputTokens: 131, outputTokens: 3, cacheReadTokens: 2, cacheWriteTokens: 1))
        #expect(
            await store.snapshot().family(.dropped)?.points == [
                .init(attributes: [.dropReason(.invalidUsage), .signal(.metrics)], value: .counter(5)),
                .init(attributes: [.dropReason(.oversize), .signal(.metrics)], value: .counter(2)),
            ])
    }

    @Test("Concurrent terminals emit one observation and reject every subsequent mutation")
    func concurrentTerminal() async throws {
        let store = MonitoringStore()
        let sink = MonitoringContextLogSink()
        let monitoring = GatewayMonitoring(store: store) {
            .init()
        } recordLog: {
            await sink.append($0)
        }
        let requestID = UUID()
        let providerID = UUID()
        let context = await monitoring.begin(requestID: requestID, route: .messages)
        await context.target(providerID: providerID, model: "provider-model")
        await context.usage(exchangeID: UUID(), totals: .init(inputTokens: 2))
        await context.estimatedInput(-1)
        await context.estimatedInput(Int.max)
        await context.estimatedInput(1)
        await context.searched()
        await context.searched()
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask {
                    await context.finish(statusCode: 200, error: index.isMultiple(of: 2) ? nil : .cancelled)
                }
            }
        }
        let before = await store.snapshot(at: .distantPast)
        await context.target(providerID: UUID(), model: "late-model")
        await context.usage(exchangeID: UUID(), totals: .init(inputTokens: 99))
        await context.invalidUsage(count: 99)
        await context.estimatedInput(99)
        await context.admission(.overloaded)
        await context.searched()
        await context.finish(statusCode: 503)
        #expect(await store.snapshot(at: .distantPast) == before)
        let entries = try await store.logs().entries
        #expect(entries.count == 1)
        #expect(await sink.entries == entries)
        let entry = try #require(entries.first)
        #expect(entry.attributes.requestID == requestID)
        #expect(entry.attributes.providerID == providerID)
        #expect(entry.attributes.resolvedModel == "provider-model")
        #expect(entry.attributes.usage == .init(inputTokens: 2))
        #expect(entry.attributes.estimatedInputTokens == Int.max)
        #expect(entry.attributes.webSearchCount == 2)
        #expect((entry.attributes.durationSeconds ?? -1) >= 0)
        #expect(before.family(.requests)?.points.map(\.value) == [.counter(1)])
        #expect(before.family(.inFlight)?.points.map(\.value) == [.gauge(0)])
    }

    @Test(
        "Every admission outcome produces its controlled terminal failure",
        arguments: MonitoringAdmissionOutcome.allCases)
    func admissionOutcomes(_ admission: MonitoringAdmissionOutcome) async throws {
        let store = MonitoringStore()
        let context = await GatewayMonitoring(store: store).begin(requestID: UUID(), route: .messages)
        await context.admission(admission)
        await context.finish(statusCode: admission == .admitted ? 200 : 503)
        let expected: MonitoringErrorKind? =
            switch admission {
            case .admitted: nil
            case .overloaded: .overloaded
            case .timedOut: .timeout
            case .invalidated: .invalidated
            case .shutdown: .shutdown
            case .internalFailure: .internalFailure
            }
        let entry = try #require(try await store.logs().entries.first)
        #expect(entry.attributes.errorKind == expected)
        let outcome: MonitoringOutcome =
            admission == .admitted ? .success : admission == .internalFailure ? .transportError : .serverError
        #expect(entry.attributes.outcome == outcome)
        let snapshot = await store.snapshot()
        if admission == .admitted {
            #expect(snapshot.family(.admissionRejections) == nil)
            #expect(snapshot.family(.admissionTimeouts) == nil)
        } else if admission == .timedOut {
            #expect(snapshot.family(.admissionTimeouts)?.points.map(\.value) == [.counter(1)])
        } else {
            #expect(
                snapshot.family(.admissionRejections)?.points == [
                    .init(attributes: [.admissionReason(admission)], value: .counter(1))
                ])
        }
    }

    @Test(
        "HTTP terminals distinguish successful, client, server and absent status",
        arguments: [Int?.none, 200, 400, 503])
    func httpOutcomes(_ status: Int?) async throws {
        let store = MonitoringStore()
        let context = await GatewayMonitoring(store: store).begin(requestID: UUID(), route: .responses)
        await context.finish(statusCode: status)
        let entry = try #require(try await store.logs().entries.first)
        let expectedOutcome: MonitoringOutcome =
            switch status {
            case nil: .transportError
            case 200: .success
            case 400: .clientError
            default: .serverError
            }
        let expectedError: MonitoringErrorKind? =
            switch status {
            case 400: .invalidRequest
            case 503: .providerHTTP
            default: nil
            }
        #expect(entry.attributes.outcome == expectedOutcome)
        #expect(entry.attributes.errorKind == expectedError)
        #expect(entry.attributes.usage == nil)
        #expect(entry.attributes.estimatedInputTokens == nil)
    }
}

private actor MonitoringContextLogSink {
    var entries: [MonitoringLogEntry] = []

    func append(_ entry: MonitoringLogEntry) { entries.append(entry) }
}
