import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import NIOCore
import NIOHTTP1

package enum GatewayCompactionTarget: Sendable {
    case native
    case managed(CodexModelTarget, credential: String?)
}

extension GatewayResponder {
    /// Compaction is a gateway-owned Responses exchange. The model selects a
    /// summary and references; only original client items enter the continuation.
    package func responsesCompactionResponse(
        plan: ResponsesCompactionPlan,
        target: GatewayCompactionTarget,
        incomingHeaders: HTTPHeaders,
        eventID: UUID
    ) async throws -> Response {
        let usesSentinel = CodexNativePassthrough.isSentinelAuthorization(incomingHeaders)
        if case .native = target, usesSentinel {
            return openAIError(status: .unauthorized, message: CodexNativePassthrough.sentinelRejectionMessage)
        }
        do {
            let result = try await compactResponses(
                plan: plan, target: target, incomingHeaders: incomingHeaders, eventID: eventID
            )
            let bytes = try ResponsesCompactionStream.encode(result, model: plan.originalModel)
            guard bytes.count <= maximumRequestBytes else {
                return openAIError(status: .contentTooLarge, message: "Compacted response is too large")
            }
            return Response(
                status: .ok,
                headers: [.contentType: "text/event-stream", .cacheControl: "no-cache"],
                body: ResponseBody(byteBuffer: ByteBuffer(bytes: bytes))
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as CompactionUpstreamFailure {
            return bufferedResponse(failure.response, body: failure.body)
        } catch ResponsesCompactionError.invalidRequest {
            return openAIError(status: .badRequest, message: "Invalid compaction request")
        } catch ResponsesCompactionError.unsupportedCompaction {
            return openAIError(status: .badRequest, message: "Compacted history requires its original provider")
        } catch {
            return openAIError(status: .badGateway, message: "Could not compact conversation")
        }
    }

    package func compactResponses(
        plan: ResponsesCompactionPlan,
        target: GatewayCompactionTarget,
        incomingHeaders: HTTPHeaders,
        eventID: UUID
    ) async throws -> ResponsesCompactionResult {
        let model: String
        let streaming: Bool
        let mode: ResponsesCompactionInputMode
        switch target {
        case .native:
            model = plan.originalModel
            streaming = true
            mode = .nativeContinuation
        case .managed(let target, _):
            model = target.model.id
            streaming = false
            mode = .transcript
        }
        var usage = ResponsesUsage(inputTokens: 0, outputTokens: 0)
        for attempt in 0..<2 {
            let body = try plan.summaryRequest(
                model: model,
                stream: streaming,
                mode: mode,
                retryingInvalidSelection: attempt > 0
            )
            let turn = try await compactionModelTurn(
                body: body,
                target: target,
                incomingHeaders: incomingHeaders,
                eventID: eventID,
                attempt: attempt
            )
            usage.add(turn.usage)
            do {
                let result = try plan.complete(responseBody: turn.rootJSON)
                return ResponsesCompactionResult(itemJSON: result.itemJSON, usage: usage)
            } catch ResponsesCompactionError.invalidResponse {
                continue
            }
        }
        throw ResponsesCompactionError.invalidResponse
    }
}

package struct CompactionUpstreamFailure: Swift.Error {
    let response: HTTPClientResponse
    let body: Data
}
