import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import NIOCore
import NIOHTTP1

package enum GatewayCompactionTarget: Sendable {
    /// A native model's own compaction: only the chatgpt.com backend can read
    /// native state, so the summary turn runs against it directly.
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
        var plan = plan
        var repair: String?
        var overflowTrimmed = false
        var usage = ResponsesUsage(inputTokens: 0, outputTokens: 0)
        var attempt = 0
        while true {
            attempt += 1
            let body = try plan.summaryRequest(
                model: Self.compactionModel(target, plan: plan),
                stream: Self.compactionStreams(target),
                mode: Self.compactionMode(target),
                repair: repair
            )
            do {
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
                } catch let error as ResponsesCompactionError {
                    guard case .invalidSelection(let reason) = error, repair == nil else {
                        throw ResponsesCompactionError.invalidResponse
                    }
                    repair = reason
                }
            } catch let failure as CompactionUpstreamFailure {
                // A context overflow retries once after shedding the oldest
                // removable transcript items, mirroring Ollama's trim.
                if !overflowTrimmed, Self.isContextLimit(failure), try plan.trimForContextLimit() > 0 {
                    overflowTrimmed = true
                    continue
                }
                throw failure
            }
        }
    }

    private static func compactionModel(
        _ target: GatewayCompactionTarget, plan: ResponsesCompactionPlan
    ) -> String {
        switch target {
        case .native: plan.originalModel
        case .managed(let target, _): target.model.id
        }
    }

    private static func compactionStreams(_ target: GatewayCompactionTarget) -> Bool {
        switch target {
        case .native: true
        case .managed: false
        }
    }

    private static func compactionMode(_ target: GatewayCompactionTarget) -> ResponsesCompactionInputMode {
        switch target {
        case .native: .nativeContinuation
        case .managed: .transcript
        }
    }

    /// Ollama's heuristic: the provider reports a context overflow either as
    /// `context_length_exceeded` or as the "prompt is too long" message shape.
    private static func isContextLimit(_ failure: CompactionUpstreamFailure) -> Bool {
        let status = failure.response.status.code
        guard status == 400 || status == 413 else { return false }
        guard let root = try? JSONSerialization.jsonObject(with: failure.body) as? [String: Any],
            let error = root["error"] as? [String: Any]
        else { return false }
        if let code = error["code"] as? String, code == "context_length_exceeded" { return true }
        guard let message = error["message"] as? String else { return false }
        return message.hasPrefix("The prompt is too long: ")
            && message.contains(", model maximum context length: ")
    }
}

package struct CompactionUpstreamFailure: Swift.Error {
    let response: HTTPClientResponse
    let body: Data
}
