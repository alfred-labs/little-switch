import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore
import NIOHTTP1

package struct ModelImageInputProber: ModelImageInputProbing {
    private let transport: any UpstreamTransport
    private let challenge: @Sendable () throws -> ModelImageProbeChallenge
    private let now: @Sendable () -> Date
    private let waitForDeadline: @Sendable () async throws -> Void

    package init(
        transport: any UpstreamTransport,
        challenge: @escaping @Sendable () throws -> ModelImageProbeChallenge = { try ModelImageProbeChallenge.make() },
        now: @escaping @Sendable () -> Date = { Date() },
        waitForDeadline: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .seconds(15)) }
    ) {
        self.transport = transport
        self.challenge = challenge
        self.now = now
        self.waitForDeadline = waitForDeadline
    }

    package func probe(
        provider: Provider,
        model: DiscoveredModel,
        wire: ModelImageInputWire,
        secret: String?
    ) async throws -> ModelImageInputProbeResult {
        try Task.checkCancellation()
        let start = now()
        let result = try await withThrowingTaskGroup(of: ModelImageInputProbeResult.self) { group in
            group.addTask {
                try await perform(provider: provider, model: model, wire: wire, secret: secret, start: start)
            }
            group.addTask {
                try await waitForDeadline()
                return self.result(.inconclusive(.timeout), start: start)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CancellationError() }
            return first
        }
        try Task.checkCancellation()
        return result
    }

    private func perform(
        provider: Provider,
        model: DiscoveredModel,
        wire: ModelImageInputWire,
        secret: String?,
        start: Date
    ) async throws -> ModelImageInputProbeResult {
        do {
            let challenge = try challenge()
            let body = try requestBody(challenge: challenge, modelID: model.id, wire: wire)
            guard body.count <= 16 * 1_024 else { return result(.inconclusive(.sizeLimit), start: start) }
            let request = try ProviderRequestBuilder.forwarding(
                api: wire == .responses ? .responses : .chatCompletions,
                provider: provider,
                secret: secret,
                headers: HTTPHeaders([("content-type", "application/json")]),
                body: body)
            let response = try await transport.execute(request, timeout: .seconds(15))
            var bytes = Data()
            for try await buffer in response.body {
                try Task.checkCancellation()
                guard buffer.readableBytes <= ModelImageProbeResponse.maximumBytes - bytes.count else {
                    return result(.inconclusive(.sizeLimit), start: start)
                }
                bytes.append(contentsOf: buffer.readableBytesView)
            }
            return result(
                ModelImageProbeResponse.classify(
                    body: bytes,
                    status: Int(clamping: response.status.code),
                    wire: wire,
                    expectedColors: challenge.expectedColors),
                usage: ModelImageProbeResponse.usage(body: bytes, wire: wire),
                start: start)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            return result(.inconclusive(.timeout), start: start)
        } catch let error as HTTPClientError where error == .deadlineExceeded || error == .readTimeout {
            return result(.inconclusive(.timeout), start: start)
        } catch {
            return result(.inconclusive(.transport), start: start)
        }
    }

    private func result(
        _ outcome: ModelImageInputProbeOutcome,
        usage: ResponsesUsage? = nil,
        start: Date
    ) -> ModelImageInputProbeResult {
        ModelImageInputProbeResult(
            outcome: outcome, usage: usage, startedAt: start, durationSeconds: max(0, now().timeIntervalSince(start)))
    }

    private func requestBody(
        challenge: ModelImageProbeChallenge,
        modelID: String,
        wire: ModelImageInputWire
    ) throws -> Data {
        let prompt =
            "Read the four tile colors: top-left, top-right, bottom-left, bottom-right. "
            + "Reply only with four names from red, green, blue, yellow, black, white."
        let url = "data:image/png;base64," + challenge.png.base64EncodedString()
        let image: [String: Any] =
            wire == .responses
            ? ["type": "input_image", "image_url": url, "detail": "low"]
            : ["type": "image_url", "image_url": ["url": url, "detail": "low"]]
        let text: [String: Any] = ["type": wire == .responses ? "input_text" : "text", "text": prompt]
        return try WireJSONCompatibility.data([
            "model": modelID,
            "stream": false,
            wire == .responses ? "max_output_tokens" : "max_tokens": 256,
            wire == .responses ? "input" : "messages": [["role": "user", "content": [text, image]]],
        ])
    }
}
