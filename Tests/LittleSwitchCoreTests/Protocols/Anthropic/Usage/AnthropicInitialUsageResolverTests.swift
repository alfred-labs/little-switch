import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

// The failure matrix and circuit-breaker concurrency cases stay together so
// their shared resolver fixtures remain reviewable as one behavioral suite.
// swiftlint:disable file_length

private struct ResolverFailureCase {
    let status: HTTPResponseStatus
    let body: String
    let outcome: AnthropicProviderCountOutcome
}

@Suite("Anthropic initial usage resolver")
// swiftlint:disable:next type_body_length
struct AnthropicInitialUsageResolverTests {
    @Test("The live deadline completes after its one-second window")
    func liveDeadlineCompletes() async throws {
        try await LiveAnthropicInitialUsageTiming().waitForDeadline()
    }

    @Test("A valid provider count wins and reports its measured latency")
    func providerCountSucceeds() async throws {
        let clock = ResolverTestClock(milliseconds: 100)
        let deadline = ResolverTestGate()
        let transport = ResolverClockAdvancingTransport(
            clock: clock,
            advanceBy: 12,
            response: countResponse(status: .ok, body: #"{"input_tokens":37}"#)
        )
        let resolver = makeResolver(clock: clock, deadline: deadline)

        let result = try await resolver.estimate(
            request: context(),
            transport: transport
        )

        #expect(result == .providerEstimate(tokens: 37, elapsedMilliseconds: 12))
        #expect(await transport.requestCount == 1)
        #expect(await deadline.cancelledWaitCount == 1)
    }

    @Test("HTTP and invalid provider responses use the exact local estimator")
    func ordinaryFailuresUseLocalEstimator() async throws {
        let body = semanticBody()
        let expected = try TokenEstimator.estimate(body)
        let cases: [ResolverFailureCase] = [
            ResolverFailureCase(status: .unauthorized, body: #"{"error":"no"}"#, outcome: .http),
            ResolverFailureCase(status: .tooManyRequests, body: #"{"error":"slow"}"#, outcome: .http),
            ResolverFailureCase(
                status: .internalServerError,
                body: #"{"error":"down"}"#,
                outcome: .http
            ),
            ResolverFailureCase(status: .ok, body: "{}", outcome: .invalid),
            ResolverFailureCase(status: .ok, body: #"{"input_tokens":0}"#, outcome: .invalid),
            ResolverFailureCase(status: .ok, body: #"{"input_tokens":2.5}"#, outcome: .invalid),
            ResolverFailureCase(status: .ok, body: "{", outcome: .invalid),
        ]

        for testCase in cases {
            let transport = ResolverStepTransport(steps: [
                .response(countResponse(status: testCase.status, body: testCase.body))
            ])
            let resolver = makeResolver()

            let result = try await resolver.estimate(
                request: context(body: body),
                transport: transport
            )

            #expect(
                result
                    == .localEstimate(
                        tokens: expected,
                        providerOutcome: testCase.outcome,
                        elapsedMilliseconds: 0
                    )
            )
        }
    }

    @Test("Transport, oversized body, projection, and builder failures fall back locally")
    func otherFailuresUseLocalEstimator() async throws {
        let body = semanticBody()
        let expected = try TokenEstimator.estimate(body)

        let transportFailure = ResolverStepTransport(steps: [.failure])
        #expect(
            try await makeResolver().estimate(
                request: context(body: body),
                transport: transportFailure
            )
                == .localEstimate(
                    tokens: expected,
                    providerOutcome: .transport,
                    elapsedMilliseconds: 0
                )
        )

        let oversized = ResolverStepTransport(steps: [
            .response(countResponse(status: .ok, body: String(repeating: "x", count: 65_537)))
        ])
        #expect(
            try await makeResolver().estimate(
                request: context(body: body),
                transport: oversized
            )
                == .localEstimate(
                    tokens: expected,
                    providerOutcome: .invalid,
                    elapsedMilliseconds: 0
                )
        )

        let fixedEstimator = ResolverRecordingEstimator(result: 11)
        let projectionResolver = makeResolver(tokenEstimator: fixedEstimator)
        #expect(
            try await projectionResolver.estimate(
                request: context(body: Data("{".utf8)),
                transport: ResolverStepTransport(steps: [])
            )
                == .localEstimate(
                    tokens: 11,
                    providerOutcome: .invalid,
                    elapsedMilliseconds: 0
                )
        )

        let missingCredentialProvider = Provider(
            name: "Missing",
            baseURL: "https://example.com",
            authMode: .bearer
        )
        let anonymousTransport = ResolverStepTransport(steps: [])
        #expect(
            try await makeResolver().estimate(
                request: context(provider: missingCredentialProvider, secret: nil, body: body),
                transport: anonymousTransport
            )
                == .localEstimate(
                    tokens: expected,
                    providerOutcome: .transport,
                    elapsedMilliseconds: 0
                )
        )
        // The probe left without an authorization header.
        let anonymousRequestCount = await anonymousTransport.requestCount
        #expect(anonymousRequestCount == 1)
    }

    @Test("The one-second deadline cancels only the auxiliary count and falls back once")
    func deadlineWins() async throws {
        let clock = ResolverTestClock(milliseconds: 500)
        let deadline = ResolverTestGate()
        let providerGate = ResolverTestGate()
        let transport = ResolverGatedTransport(gate: providerGate)
        let estimator = ResolverRecordingEstimator(result: 23)
        let resolver = makeResolver(
            tokenEstimator: estimator,
            clock: clock,
            deadline: deadline
        )

        let task = Task {
            try await resolver.estimate(request: context(), transport: transport)
        }
        try await providerGate.waitUntilEntered(count: 1)
        clock.advance(by: 1_000)
        await deadline.releaseAll()

        #expect(
            try await task.value
                == .localEstimate(
                    tokens: 23,
                    providerOutcome: .timeout,
                    elapsedMilliseconds: 1_000
                )
        )
        #expect(await transport.observedCancellation)
        #expect(estimator.callCount == 1)
    }

    @Test("Parent cancellation remains cancellation and never estimates locally")
    func parentCancellationWins() async throws {
        let deadline = ResolverTestGate()
        let providerGate = ResolverTestGate()
        let transport = ResolverGatedTransport(gate: providerGate)
        let estimator = ResolverRecordingEstimator(result: 99)
        let resolver = makeResolver(tokenEstimator: estimator, deadline: deadline)

        let task = Task {
            try await resolver.estimate(request: context(), transport: transport)
        }
        try await providerGate.waitUntilEntered(count: 1)
        try await deadline.waitUntilEntered(count: 1)
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(estimator.callCount == 0)
        #expect(await transport.observedCancellation)
    }

    @Test("Circuit breaker admits every healthy request without a concurrency cap")
    func healthyCircuitHasNoConcurrencyCap() async {
        let breaker = AnthropicCountCircuitBreaker()
        let providerID = UUID()

        let admissions = await withTaskGroup(
            of: AnthropicCountCircuitBreaker.Admission.self,
            returning: [AnthropicCountCircuitBreaker.Admission].self
        ) { group in
            for _ in 0..<32 {
                group.addTask {
                    await breaker.admit(providerID: providerID, nowMilliseconds: 0)
                }
            }
            var values: [AnthropicCountCircuitBreaker.Admission] = []
            for await value in group {
                values.append(value)
            }
            return values
        }

        #expect(admissions.count == 32)
        #expect(admissions.allSatisfy { $0.permit?.isProbe == false })
    }

    @Test("A 429 opens immediately and allows exactly one probe after 30 seconds")
    func rateLimitOpensImmediately() async throws {
        let breaker = AnthropicCountCircuitBreaker()
        let providerID = UUID()
        let admission = await breaker.admit(providerID: providerID, nowMilliseconds: 10)
        let permit = try #require(admission.permit)
        #expect(!permit.isProbe)

        try await breaker.recordFailure(
            providerID: providerID,
            failure: .http(429),
            permit: permit,
            nowMilliseconds: 10
        )

        #expect(await breaker.admit(providerID: providerID, nowMilliseconds: 29_999) == .circuitOpen)
        #expect(await breaker.admit(providerID: providerID, nowMilliseconds: 30_009) == .circuitOpen)
        let probe = await breaker.admit(providerID: providerID, nowMilliseconds: 30_010)
        #expect(probe.permit?.isProbe == true)
        #expect(await breaker.admit(providerID: providerID, nowMilliseconds: 30_010) == .circuitOpen)
    }

    @Test("Three consecutive ordinary failures open, while success resets the streak")
    func ordinaryFailureThresholdAndReset() async throws {
        let breaker = AnthropicCountCircuitBreaker()
        let providerID = UUID()

        for now in 0..<2 {
            let permit = try #require(
                await breaker.admit(
                    providerID: providerID,
                    nowMilliseconds: UInt64(now)
                ).permit
            )
            try await breaker.recordFailure(
                providerID: providerID,
                failure: .transport,
                permit: permit,
                nowMilliseconds: UInt64(now)
            )
        }
        let successPermit = try #require(
            await breaker.admit(providerID: providerID, nowMilliseconds: 2).permit
        )
        try await breaker.recordSuccess(providerID: providerID, permit: successPermit)
        for now in 2..<4 {
            let permit = try #require(
                await breaker.admit(
                    providerID: providerID,
                    nowMilliseconds: UInt64(now)
                ).permit
            )
            try await breaker.recordFailure(
                providerID: providerID,
                failure: .invalid,
                permit: permit,
                nowMilliseconds: UInt64(now)
            )
        }
        let finalPermit = try #require(
            await breaker.admit(providerID: providerID, nowMilliseconds: 4).permit
        )
        try await breaker.recordFailure(
            providerID: providerID,
            failure: .timeout,
            permit: finalPermit,
            nowMilliseconds: 4
        )
        #expect(await breaker.admit(providerID: providerID, nowMilliseconds: 5) == .circuitOpen)
    }

    @Test("Half-open success closes, failure reopens, and providers stay isolated")
    func halfOpenAndProviderIsolation() async throws {
        let breaker = AnthropicCountCircuitBreaker()
        let failingProvider = UUID()
        let healthyProvider = UUID()

        let initialPermit = try #require(
            await breaker.admit(providerID: failingProvider, nowMilliseconds: 0).permit
        )
        try await breaker.recordFailure(
            providerID: failingProvider,
            failure: .http(429),
            permit: initialPermit,
            nowMilliseconds: 0
        )
        #expect(
            await breaker.admit(providerID: healthyProvider, nowMilliseconds: 1)
                .permit?.isProbe == false
        )
        let firstProbe = try #require(
            await breaker.admit(providerID: failingProvider, nowMilliseconds: 30_000).permit
        )
        #expect(firstProbe.isProbe)
        try await breaker.recordFailure(
            providerID: failingProvider,
            failure: .transport,
            permit: firstProbe,
            nowMilliseconds: 30_000
        )
        #expect(await breaker.admit(providerID: failingProvider, nowMilliseconds: 59_999) == .circuitOpen)
        let secondProbe = try #require(
            await breaker.admit(providerID: failingProvider, nowMilliseconds: 60_000).permit
        )
        #expect(secondProbe.isProbe)
        try await breaker.recordSuccess(providerID: failingProvider, permit: secondProbe)
        #expect(
            await breaker.admit(providerID: failingProvider, nowMilliseconds: 60_001)
                .permit?.isProbe == false
        )
    }

    @Test("Stale healthy completions cannot close an open or half-open generation")
    func staleSuccessCannotCloseNewGeneration() async throws {
        let breaker = AnthropicCountCircuitBreaker()
        let providerID = UUID()
        let stalePermit = try #require(
            await breaker.admit(providerID: providerID, nowMilliseconds: 0).permit
        )
        let openingPermit = try #require(
            await breaker.admit(providerID: providerID, nowMilliseconds: 0).permit
        )

        try await breaker.recordFailure(
            providerID: providerID,
            failure: .http(429),
            permit: openingPermit,
            nowMilliseconds: 0
        )
        try await breaker.recordSuccess(providerID: providerID, permit: stalePermit)
        #expect(await breaker.admit(providerID: providerID, nowMilliseconds: 1) == .circuitOpen)

        let probe = try #require(
            await breaker.admit(providerID: providerID, nowMilliseconds: 30_000).permit
        )
        #expect(probe.isProbe)
        try await breaker.recordSuccess(providerID: providerID, permit: stalePermit)
        #expect(await breaker.admit(providerID: providerID, nowMilliseconds: 30_000) == .circuitOpen)

        try await breaker.recordSuccess(providerID: providerID, permit: probe)
        #expect(
            await breaker.admit(providerID: providerID, nowMilliseconds: 30_001)
                .permit?.isProbe == false
        )
    }

    @Test("A cancelled completion cannot reset the failure streak")
    func cancelledCompletionIsNeutral() async throws {
        let breaker = AnthropicCountCircuitBreaker()
        let providerID = UUID()

        let firstFailure = try #require(
            await breaker.admit(providerID: providerID, nowMilliseconds: 0).permit
        )
        try await breaker.recordFailure(
            providerID: providerID,
            failure: .transport,
            permit: firstFailure,
            nowMilliseconds: 0
        )

        let cancelledSuccess = try #require(
            await breaker.admit(providerID: providerID, nowMilliseconds: 1).permit
        )
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await breaker.recordSuccess(
                providerID: providerID,
                permit: cancelledSuccess
            )
        }
        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        for now in 2...3 {
            let permit = try #require(
                await breaker.admit(
                    providerID: providerID,
                    nowMilliseconds: UInt64(now)
                ).permit
            )
            try await breaker.recordFailure(
                providerID: providerID,
                failure: .invalid,
                permit: permit,
                nowMilliseconds: UInt64(now)
            )
        }
        #expect(await breaker.admit(providerID: providerID, nowMilliseconds: 4) == .circuitOpen)
    }

    @Test("An open circuit skips transport and reports zero count-call latency")
    func openCircuitSkipsTransport() async throws {
        let breaker = AnthropicCountCircuitBreaker()
        let provider = provider()
        let permit = try #require(
            await breaker.admit(providerID: provider.id, nowMilliseconds: 0).permit
        )
        try await breaker.recordFailure(
            providerID: provider.id,
            failure: .http(429),
            permit: permit,
            nowMilliseconds: 0
        )
        let transport = ResolverStepTransport(steps: [])
        let resolver = makeResolver(circuitBreaker: breaker)

        let result = try await resolver.estimate(
            request: context(provider: provider),
            transport: transport
        )

        #expect(
            result
                == .localEstimate(
                    tokens: try TokenEstimator.estimate(semanticBody()),
                    providerOutcome: .circuitOpen,
                    elapsedMilliseconds: 0
                )
        )
        #expect(await transport.requestCount == 0)
    }

    @Test("Concurrent half-open requests allow one provider probe and fall back immediately")
    func concurrentHalfOpenRequestsUseOneProbe() async throws {
        let breaker = AnthropicCountCircuitBreaker()
        let provider = provider()
        let openingPermit = try #require(
            await breaker.admit(providerID: provider.id, nowMilliseconds: 0).permit
        )
        try await breaker.recordFailure(
            providerID: provider.id,
            failure: .http(429),
            permit: openingPermit,
            nowMilliseconds: 0
        )

        let clock = ResolverTestClock(milliseconds: 30_000)
        let deadline = ResolverTestGate()
        let providerGate = ResolverTestGate()
        let probeTransport = ResolverGatedTransport(gate: providerGate)
        let estimator = ResolverRecordingEstimator(result: 23)
        let resolver = makeResolver(
            tokenEstimator: estimator,
            clock: clock,
            deadline: deadline,
            circuitBreaker: breaker
        )
        let probeTask = Task {
            try await resolver.estimate(
                request: context(provider: provider),
                transport: probeTransport
            )
        }
        try await providerGate.waitUntilEntered(count: 1)

        let fallbackResults = try await withThrowingTaskGroup(
            of: AnthropicInitialUsageResolution.self,
            returning: [AnthropicInitialUsageResolution].self
        ) { group in
            for _ in 0..<8 {
                group.addTask {
                    try await resolver.estimate(
                        request: context(provider: provider),
                        transport: ResolverStepTransport(steps: [])
                    )
                }
            }
            var results: [AnthropicInitialUsageResolution] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }

        #expect(fallbackResults.count == 8)
        #expect(
            fallbackResults.allSatisfy {
                $0
                    == .localEstimate(
                        tokens: 23,
                        providerOutcome: .circuitOpen,
                        elapsedMilliseconds: 0
                    )
            }
        )
        #expect(estimator.callCount == 8)

        await providerGate.releaseAll()
        #expect(
            try await probeTask.value
                == .providerEstimate(tokens: 99, elapsedMilliseconds: 0)
        )
    }

    @Test("Gateway defaults share the configured local token estimator")
    func gatewayDependenciesShareEstimator() async throws {
        let estimator = ResolverRecordingEstimator(result: 71)
        let dependencies = GatewayResponderDependencies(tokenEstimator: estimator)

        let result = try await dependencies.initialUsageResolver.estimate(
            request: context(),
            transport: ResolverStepTransport(steps: [.failure])
        )

        guard case .localEstimate(let tokens, .transport, _) = result else {
            Issue.record("Expected transport fallback")
            return
        }
        #expect(tokens == 71)
        #expect(estimator.callCount == 1)
    }

    @Test("Live deadline timing preserves task cancellation")
    func liveTimingCancellation() async {
        let timing = LiveAnthropicInitialUsageTiming()
        let task = Task { try await timing.waitForDeadline() }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test("Abandoned half-open probes can be retried and stale failures stay neutral")
    func abandonedAndStaleProbeState() async throws {
        let breaker = AnthropicCountCircuitBreaker()
        let providerID = UUID()
        let stale = try #require(
            await breaker.admit(providerID: providerID, nowMilliseconds: 0).permit
        )
        let opening = try #require(
            await breaker.admit(providerID: providerID, nowMilliseconds: 0).permit
        )
        try await breaker.recordFailure(
            providerID: providerID,
            failure: .http(429),
            permit: opening,
            nowMilliseconds: 0
        )
        try await breaker.recordFailure(
            providerID: providerID,
            failure: .transport,
            permit: stale,
            nowMilliseconds: 1
        )

        let probe = try #require(
            await breaker.admit(providerID: providerID, nowMilliseconds: 30_000).permit
        )
        await breaker.abandon(providerID: providerID, permit: stale)
        await breaker.abandon(providerID: providerID, permit: probe)
        let retried = try #require(
            await breaker.admit(providerID: providerID, nowMilliseconds: 30_000).permit
        )
        #expect(retried.isProbe)
    }

    @Test("Cancelling a resolver probe abandons it for the next caller")
    func cancelledResolverProbeIsAbandoned() async throws {
        let breaker = AnthropicCountCircuitBreaker()
        let provider = provider()
        let opening = try #require(
            await breaker.admit(providerID: provider.id, nowMilliseconds: 0).permit
        )
        try await breaker.recordFailure(
            providerID: provider.id,
            failure: .http(429),
            permit: opening,
            nowMilliseconds: 0
        )
        let clock = ResolverTestClock(milliseconds: 30_000)
        let deadline = ResolverTestGate()
        let providerGate = ResolverTestGate()
        let transport = ResolverGatedTransport(gate: providerGate)
        let resolver = makeResolver(
            clock: clock,
            deadline: deadline,
            circuitBreaker: breaker
        )
        let task = Task {
            try await resolver.estimate(
                request: context(provider: provider),
                transport: transport
            )
        }
        try await providerGate.waitUntilEntered(count: 1)
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(
            await breaker.admit(providerID: provider.id, nowMilliseconds: 30_000)
                .permit?.isProbe == true
        )
    }

    @Test("Cancellation raised by a successful response body remains cancellation")
    func responseBodyCancellation() async {
        let response = HTTPClientResponse(
            status: .ok,
            body: .stream(
                ResolverCancellingResponseSequence(body: #"{"input_tokens":19}"#)
            )
        )
        let resolver = makeResolver()

        await #expect(throws: CancellationError.self) {
            try await resolver.estimate(
                request: context(),
                transport: ResolverStepTransport(steps: [.response(response)])
            )
        }
    }

    private func makeResolver(
        tokenEstimator: any GatewayTokenEstimating = LiveGatewayTokenEstimator(),
        clock: ResolverTestClock = ResolverTestClock(milliseconds: 0),
        deadline: ResolverTestGate = ResolverTestGate(),
        circuitBreaker: AnthropicCountCircuitBreaker = AnthropicCountCircuitBreaker()
    ) -> LiveAnthropicInitialUsageResolver {
        LiveAnthropicInitialUsageResolver(
            tokenEstimator: tokenEstimator,
            timing: ResolverTestTiming(clock: clock, deadline: deadline),
            circuitBreaker: circuitBreaker
        )
    }

    private func provider() -> Provider {
        Provider(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 17)),
            name: "Provider",
            baseURL: "https://provider.example.com/anthropic",
            authMode: .bearer
        )
    }

    private func context(
        provider: Provider? = nil,
        secret: String? = "secret",
        body: Data? = nil
    ) -> AnthropicInitialUsageRequestContext {
        AnthropicInitialUsageRequestContext(
            provider: provider ?? self.provider(),
            secret: secret,
            incomingHeaders: [
                "content-type": "application/json",
                "anthropic-version": "2023-06-01",
            ],
            upstreamBody: body ?? semanticBody()
        )
    }

    private func semanticBody() -> Data {
        Data(
            // swiftlint:disable:next line_length
            #"{"messages":[{"content":[{"text":"héllo 👋","type":"text"},{"source":{"data":"ignored","media_type":"image/png","type":"base64"},"type":"image"}],"role":"user"}],"model":"large","system":"réponds","tools":[{"description":"cherche","input_schema":{"properties":{"q":{"type":"string"}},"type":"object"},"name":"search"}]}"#
                .utf8
        )
    }

    private func countResponse(status: HTTPResponseStatus, body: String) -> HTTPClientResponse {
        HTTPClientResponse(
            status: status,
            headers: ["content-type": "application/json"],
            body: .bytes(ByteBuffer(string: body))
        )
    }
}
