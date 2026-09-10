import AsyncHTTPClient
import Dispatch
import Foundation
import LittleSwitchTransport
import NIOCore
import NIOHTTP1

package enum AnthropicProviderCountOutcome: String, Codable, Equatable, Sendable {
    case success
    case timeout
    case http
    case invalid
    case transport
    case circuitOpen
}

package enum AnthropicInitialUsageResolution: Equatable, Sendable {
    case native(Int)
    case providerEstimate(tokens: Int, elapsedMilliseconds: Int)
    case localEstimate(
        tokens: Int,
        providerOutcome: AnthropicProviderCountOutcome,
        elapsedMilliseconds: Int
    )
}

package struct AnthropicInitialUsageRequestContext: Sendable {
    let provider: Provider
    let secret: String?
    let incomingHeaders: HTTPHeaders
    let upstreamBody: Data

    package init(
        provider: Provider,
        secret: String?,
        incomingHeaders: HTTPHeaders,
        upstreamBody: Data
    ) {
        self.provider = provider
        self.secret = secret
        self.incomingHeaders = incomingHeaders
        self.upstreamBody = upstreamBody
    }
}

package protocol AnthropicInitialUsageResolving: Sendable {
    func estimate(
        request: AnthropicInitialUsageRequestContext,
        transport: any UpstreamTransport
    ) async throws -> AnthropicInitialUsageResolution
}

package protocol AnthropicInitialUsageTiming: Sendable {
    func nowMilliseconds() -> UInt64
    func waitForDeadline() async throws
}

package struct LiveAnthropicInitialUsageTiming: AnthropicInitialUsageTiming {
    package init() {}

    package func nowMilliseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds / 1_000_000
    }

    package func waitForDeadline() async throws {
        try await Task.sleep(for: .seconds(1))
    }
}

package enum AnthropicCountCircuitFailure: Equatable, Sendable {
    case timeout
    case http(Int)
    case invalid
    case transport

    var outcome: AnthropicProviderCountOutcome {
        switch self {
        case .timeout:
            .timeout
        case .http:
            .http
        case .invalid:
            .invalid
        case .transport:
            .transport
        }
    }

    var opensImmediately: Bool {
        self == .http(429)
    }
}

package actor AnthropicCountCircuitBreaker {
    package struct Permit: Equatable, Sendable {
        fileprivate enum Kind: Equatable, Sendable {
            case closed
            case halfOpenProbe
        }

        fileprivate let generation: UInt64
        fileprivate let kind: Kind

        package var isProbe: Bool { kind == .halfOpenProbe }
    }

    package enum Admission: Equatable, Sendable {
        case request(Permit)
        case circuitOpen

        package var permit: Permit? {
            guard case .request(let permit) = self else { return nil }
            return permit
        }
    }

    private enum State: Sendable {
        case closed(generation: UInt64, consecutiveFailures: Int)
        case open(generation: UInt64, untilMilliseconds: UInt64)
        case halfOpen(generation: UInt64, probeInFlight: Bool)
    }

    private let failureThreshold: Int
    private let openDurationMilliseconds: UInt64
    private var states: [UUID: State] = [:]

    package init(
        failureThreshold: Int = 3,
        openDurationMilliseconds: UInt64 = 30_000
    ) {
        self.failureThreshold = max(1, failureThreshold)
        self.openDurationMilliseconds = openDurationMilliseconds
    }

    package func admit(providerID: UUID, nowMilliseconds: UInt64) -> Admission {
        switch states[providerID] ?? .closed(generation: 0, consecutiveFailures: 0) {
        case .closed(let generation, _):
            return .request(Permit(generation: generation, kind: .closed))
        case .open(_, let untilMilliseconds) where nowMilliseconds < untilMilliseconds:
            return .circuitOpen
        case .open(let generation, _):
            states[providerID] = .halfOpen(generation: generation, probeInFlight: true)
            return .request(Permit(generation: generation, kind: .halfOpenProbe))
        case .halfOpen(_, probeInFlight: true):
            return .circuitOpen
        case .halfOpen(let generation, probeInFlight: false):
            states[providerID] = .halfOpen(generation: generation, probeInFlight: true)
            return .request(Permit(generation: generation, kind: .halfOpenProbe))
        }
    }

    package func recordSuccess(providerID: UUID, permit: Permit) throws {
        try Task.checkCancellation()
        switch (states[providerID] ?? .closed(generation: 0, consecutiveFailures: 0), permit.kind) {
        case (.closed(let generation, _), .closed) where generation == permit.generation:
            states[providerID] = .closed(generation: generation, consecutiveFailures: 0)
        case (.halfOpen(let generation, probeInFlight: true), .halfOpenProbe)
        where generation == permit.generation:
            states[providerID] = .closed(
                generation: nextGeneration(after: generation),
                consecutiveFailures: 0
            )
        default:
            break
        }
    }

    package func recordFailure(
        providerID: UUID,
        failure: AnthropicCountCircuitFailure,
        permit: Permit,
        nowMilliseconds: UInt64
    ) throws {
        try Task.checkCancellation()

        switch (states[providerID] ?? .closed(generation: 0, consecutiveFailures: 0), permit.kind) {
        // swiftlint:disable:next pattern_matching_keywords
        case (.closed(let generation, let consecutiveFailures), .closed)
        where generation == permit.generation:
            let next = consecutiveFailures + 1
            if failure.opensImmediately || next >= failureThreshold {
                open(
                    providerID: providerID,
                    generation: nextGeneration(after: generation),
                    nowMilliseconds: nowMilliseconds
                )
            } else {
                states[providerID] = .closed(
                    generation: generation,
                    consecutiveFailures: next
                )
            }
        case (.halfOpen(let generation, probeInFlight: true), .halfOpenProbe)
        where generation == permit.generation:
            open(
                providerID: providerID,
                generation: nextGeneration(after: generation),
                nowMilliseconds: nowMilliseconds
            )
        default:
            // Older healthy-state requests and replaced probes cannot mutate
            // the newer circuit generation.
            break
        }
    }

    package func abandon(providerID: UUID, permit: Permit) {
        guard permit.kind == .halfOpenProbe,
            case .halfOpen(let generation, probeInFlight: true) = states[providerID],
            generation == permit.generation
        else {
            return
        }
        states[providerID] = .halfOpen(generation: generation, probeInFlight: false)
    }

    private func open(
        providerID: UUID,
        generation: UInt64,
        nowMilliseconds: UInt64
    ) {
        let deadline = nowMilliseconds.addingReportingOverflow(openDurationMilliseconds)
        states[providerID] = .open(
            generation: generation,
            untilMilliseconds: deadline.overflow ? UInt64.max : deadline.partialValue
        )
    }

    private func nextGeneration(after generation: UInt64) -> UInt64 {
        generation == UInt64.max ? 0 : generation + 1
    }
}

package struct LiveAnthropicInitialUsageResolver: AnthropicInitialUsageResolving {
    private enum CountAttempt: Sendable {
        case success(Int)
        case failure(AnthropicCountCircuitFailure)
    }

    private enum RaceWinner: Sendable {
        case provider(CountAttempt)
        case deadline
    }

    private let tokenEstimator: any GatewayTokenEstimating
    private let timing: any AnthropicInitialUsageTiming
    private let circuitBreaker: AnthropicCountCircuitBreaker
    private let maximumResponseBytes: Int

    package init(
        tokenEstimator: any GatewayTokenEstimating,
        timing: any AnthropicInitialUsageTiming = LiveAnthropicInitialUsageTiming(),
        circuitBreaker: AnthropicCountCircuitBreaker = AnthropicCountCircuitBreaker(),
        maximumResponseBytes: Int = 64 * 1_024
    ) {
        self.tokenEstimator = tokenEstimator
        self.timing = timing
        self.circuitBreaker = circuitBreaker
        self.maximumResponseBytes = max(0, maximumResponseBytes)
    }

    package func estimate(
        request: AnthropicInitialUsageRequestContext,
        transport: any UpstreamTransport
    ) async throws -> AnthropicInitialUsageResolution {
        try Task.checkCancellation()

        let countRequest: HTTPClientRequest
        do {
            let projected = try AnthropicCountTokensRequest.project(request.upstreamBody)
            countRequest = try ProviderRequestBuilder.countTokens(
                provider: request.provider,
                secret: request.secret,
                headers: request.incomingHeaders,
                body: projected
            )
        } catch {
            return try localEstimate(
                request: request,
                outcome: .invalid,
                elapsedMilliseconds: 0
            )
        }

        let admission = await circuitBreaker.admit(
            providerID: request.provider.id,
            nowMilliseconds: timing.nowMilliseconds()
        )
        guard case .request(let permit) = admission else {
            return try localEstimate(
                request: request,
                outcome: .circuitOpen,
                elapsedMilliseconds: 0
            )
        }

        let startedAt = timing.nowMilliseconds()
        do {
            let attempt = try await raceCountAgainstDeadline(
                countRequest,
                transport: transport
            )
            let elapsed = elapsedMilliseconds(since: startedAt)
            switch attempt {
            case .success(let count):
                try Task.checkCancellation()
                try await circuitBreaker.recordSuccess(
                    providerID: request.provider.id,
                    permit: permit
                )
                return .providerEstimate(tokens: count, elapsedMilliseconds: elapsed)
            case .failure(let failure):
                try Task.checkCancellation()
                try await circuitBreaker.recordFailure(
                    providerID: request.provider.id,
                    failure: failure,
                    permit: permit,
                    nowMilliseconds: timing.nowMilliseconds()
                )
                return try localEstimate(
                    request: request,
                    outcome: failure.outcome,
                    elapsedMilliseconds: elapsed
                )
            }
        } catch is CancellationError {
            if permit.isProbe {
                await circuitBreaker.abandon(
                    providerID: request.provider.id,
                    permit: permit
                )
            }
            throw CancellationError()
        }
    }

    private func raceCountAgainstDeadline(
        _ request: HTTPClientRequest,
        transport: any UpstreamTransport
    ) async throws -> CountAttempt {
        try await withThrowingTaskGroup(of: RaceWinner.self) { group in
            group.addTask {
                .provider(try await providerCount(request, transport: transport))
            }
            group.addTask {
                try await timing.waitForDeadline()
                return .deadline
            }

            // Two children are installed before iteration, so the first element exists.
            // swiftlint:disable:next force_unwrapping
            let winner = try await group.next()!
            group.cancelAll()
            switch winner {
            case .provider(let attempt):
                return attempt
            case .deadline:
                return .failure(.timeout)
            }
        }
    }

    private func providerCount(
        _ request: HTTPClientRequest,
        transport: any UpstreamTransport
    ) async throws -> CountAttempt {
        let response: HTTPClientResponse
        do {
            response = try await transport.execute(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .failure(.transport)
        }
        guard (200..<300).contains(response.status.code) else {
            return .failure(.http(Int(response.status.code)))
        }
        do {
            let buffer = try await response.body.collect(upTo: maximumResponseBytes)
            try Task.checkCancellation()
            let count = try AnthropicCountTokensRequest.parseCount(
                Data(buffer.readableBytesView)
            )
            return .success(count)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .failure(.invalid)
        }
    }

    private func localEstimate(
        request: AnthropicInitialUsageRequestContext,
        outcome: AnthropicProviderCountOutcome,
        elapsedMilliseconds: Int
    ) throws -> AnthropicInitialUsageResolution {
        try Task.checkCancellation()
        let count = try tokenEstimator.estimate(request.upstreamBody)
        try Task.checkCancellation()
        return .localEstimate(
            tokens: count,
            providerOutcome: outcome,
            elapsedMilliseconds: elapsedMilliseconds
        )
    }

    private func elapsedMilliseconds(since start: UInt64) -> Int {
        let now = timing.nowMilliseconds()
        let elapsed = now >= start ? now - start : 0
        return Int(clamping: elapsed)
    }
}
