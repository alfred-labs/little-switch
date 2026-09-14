import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import LittleSwitchCommon
import NIOCore
import NIOHTTP1

/// Only catalog-managed models use the gateway's summary adapter. Native
/// compaction belongs to the upstream Responses protocol and bypasses it.
package struct GatewayCompactionTarget: Sendable {
    let route: CodexModelTarget
    let credential: String?
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
        try await compactResponses(
            target: target,
            incomingHeaders: incomingHeaders,
            eventID: eventID,
            attempt: CompactionAttempt(plan: plan)
        )
    }

    /// Bounded recursion state: one selection repair and one context-overflow
    /// trim, so at most three model turns serve a single compaction.
    private struct CompactionAttempt {
        let plan: ResponsesCompactionPlan
        let number: Int
        let repair: String?
        let overflowTrimmed: Bool
        let usage: ResponsesUsage

        init(
            plan: ResponsesCompactionPlan,
            number: Int = 1,
            repair: String? = nil,
            overflowTrimmed: Bool = false,
            usage: ResponsesUsage = ResponsesUsage(inputTokens: 0, outputTokens: 0)
        ) {
            self.plan = plan
            self.number = number
            self.repair = repair
            self.overflowTrimmed = overflowTrimmed
            self.usage = usage
        }
    }

    private func compactResponses(
        target: GatewayCompactionTarget,
        incomingHeaders: HTTPHeaders,
        eventID: UUID,
        attempt: CompactionAttempt
    ) async throws -> ResponsesCompactionResult {
        var usage = attempt.usage
        var plan = attempt.plan
        let body = try plan.summaryRequest(
            model: target.route.model.id,
            stream: false,
            repair: attempt.repair
        )
        do {
            let turn = try await compactionModelTurn(
                body: body,
                target: target,
                incomingHeaders: incomingHeaders,
                eventID: eventID,
                attempt: attempt.number
            )
            usage.add(turn.usage)
            do {
                let result = try plan.complete(responseBody: turn.rootJSON)
                return ResponsesCompactionResult(itemJSON: result.itemJSON, usage: usage)
            } catch let error as ResponsesCompactionError {
                guard case .invalidSelection(let reason) = error, attempt.repair == nil else {
                    throw ResponsesCompactionError.invalidResponse
                }
                let next = CompactionAttempt(
                    plan: plan,
                    number: attempt.number + 1,
                    repair: reason,
                    overflowTrimmed: attempt.overflowTrimmed,
                    usage: usage
                )
                return try await compactResponses(
                    target: target, incomingHeaders: incomingHeaders, eventID: eventID, attempt: next)
            }
        } catch let failure as CompactionUpstreamFailure {
            // A context overflow retries once after shedding the oldest
            // removable transcript items, mirroring Ollama's trim.
            guard !attempt.overflowTrimmed, Self.isContextLimit(failure),
                try plan.trimForContextLimit() > 0
            else { throw failure }
            let next = CompactionAttempt(
                plan: plan,
                number: attempt.number + 1,
                repair: attempt.repair,
                overflowTrimmed: true,
                usage: usage
            )
            return try await compactResponses(
                target: target, incomingHeaders: incomingHeaders, eventID: eventID, attempt: next)
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
