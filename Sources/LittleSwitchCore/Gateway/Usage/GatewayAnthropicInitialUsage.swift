import AsyncHTTPClient
import Foundation
import Hummingbird
import LittleSwitchCommon
import NIOCore
import NIOHTTP1

extension GatewayResponder {
    package func anthropicInitialUsageResponse(
        _ upstream: HTTPClientResponse,
        context: MessageAttemptContext,
        attempt: Int,
        requestBody: Data,
        trace: GatewayUpstreamResponseTrace
    ) -> Response {
        guard context.streaming,
            (200..<300).contains(upstream.status.code),
            upstream.headers["content-type"].contains(where: {
                $0.lowercased().contains("text/event-stream")
            })
        else {
            return streamingResponse(
                upstream,
                eventID: context.eventID,
                attempt: attempt,
                errorStyle: .anthropic,
                trace: trace
            )
        }

        let recorder = trafficRecorder
        let resolver = dependencies.initialUsageResolver
        let transport = transport
        let upstreamBody = upstream.body
        let resolutionRequest = AnthropicInitialUsageRequestContext(
            provider: context.target.provider,
            secret: context.secret,
            incomingHeaders: context.incomingHeaders,
            upstreamBody: requestBody
        )

        return Response(
            status: HTTPResponse.Status(
                code: Int(upstream.status.code),
                reasonPhrase: upstream.status.reasonPhrase
            ),
            headers: gatewayRewrittenResponseHeaders(upstream.headers),
            body: ResponseBody(contentLength: nil) { writer in
                var normalizer = AnthropicInitialUsageNormalizer()
                defer { trace.finish() }

                do {
                    for try await buffer in upstreamBody {
                        let bytes = Data(buffer.readableBytesView)
                        trace.append(bytes)
                        try Task.checkCancellation()

                        switch normalizer.append(bytes) {
                        case .buffering:
                            break
                        case .native(_, let output), .output(let output):
                            try await writeAnthropicInitialUsage(output, to: &writer)
                        case .estimateRequired:
                            let resolution = try await resolver.estimate(
                                request: resolutionRequest,
                                transport: transport
                            )
                            try Task.checkCancellation()
                            if let estimate = anthropicTrafficEstimate(for: resolution) {
                                await GatewayMonitoringScope.current?.estimatedInput(estimate.tokenCount)
                                recorder.record(
                                    eventID: context.eventID,
                                    action: .initialUsageEstimate(estimate)
                                )
                            }
                            try await writeAnthropicInitialUsage(
                                normalizer.resolve(resolution),
                                to: &writer
                            )
                        }
                    }

                    try Task.checkCancellation()
                    try await writeAnthropicInitialUsage(normalizer.finish(), to: &writer)
                    try Task.checkCancellation()
                    try await writer.finish(nil)
                } catch let error as ProviderToolContract.Error {
                    let frame = providerToolFailureFrame(style: .anthropic, error: error, eventID: context.eventID)
                    try await writer.write(ByteBuffer(bytes: frame))
                    try await writer.finish(nil)
                    throw GatewayCommittedStreamFailure(reason: "Provider tool contract rejected", toolError: error)
                }
            }
        )
    }
}

package func gatewayRewrittenResponseHeaders(_ upstream: HTTPHeaders) -> HTTPFields {
    var headers = upstream
    for name in [
        "content-length",
        "content-md5",
        "digest",
        "content-digest",
        "repr-digest",
        "etag",
    ] {
        headers.remove(name: name)
    }
    return gatewayResponseHeaders(headers)
}

private func writeAnthropicInitialUsage<Writer: ResponseBodyWriter>(
    _ chunks: [Data],
    to writer: inout Writer
) async throws {
    for chunk in chunks where !chunk.isEmpty {
        try Task.checkCancellation()
        try await writer.write(ByteBuffer(bytes: chunk))
    }
}

package func anthropicTrafficEstimate(
    for resolution: AnthropicInitialUsageResolution
) -> TrafficInitialUsageEstimate? {
    switch resolution {
    case .native:
        nil
    // swiftlint:disable:next pattern_matching_keywords
    case .providerEstimate(let tokens, let elapsedMilliseconds):
        TrafficInitialUsageEstimate(
            tokenCount: tokens,
            source: .provider,
            providerOutcome: .success,
            elapsedMilliseconds: elapsedMilliseconds
        )
    // swiftlint:disable:next pattern_matching_keywords
    case .localEstimate(let tokens, let providerOutcome, let elapsedMilliseconds):
        TrafficInitialUsageEstimate(
            tokenCount: tokens,
            source: .localDividedByFour,
            providerOutcome: anthropicTrafficProviderOutcome(providerOutcome),
            elapsedMilliseconds: elapsedMilliseconds
        )
    }
}

package func anthropicTrafficProviderOutcome(
    _ outcome: AnthropicProviderCountOutcome
) -> TrafficProviderCountOutcome {
    switch outcome {
    case .success:
        .success
    case .timeout:
        .timeout
    case .http:
        .http
    case .invalid:
        .invalid
    case .transport:
        .transport
    case .circuitOpen:
        .circuitOpen
    }
}
