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
        } catch ResponsesCompactionError.responseTooLarge {
            return openAIError(status: .contentTooLarge, message: "Compacted response is too large")
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
        var attempt = CompactionAttempt(
            plan: plan,
            wire: await resolvesChatCompletionsAdapter(target.route.provider) ? .chatCompletions : .responses)
        while true {
            try Task.checkCancellation()
            let acceptsImages = try await acceptsResponsesImages(
                target: target.route, wire: attempt.wire, forceText: attempt.budget.imageFallbackUsed)
            if !acceptsImages { attempt.plan = try attempt.plan.preservingUninspectedImages() }
            let body = try attempt.plan.summaryRequest(
                model: target.route.model.id, stream: false, repair: attempt.repair, acceptsImages: acceptsImages)
            attempt.budget = try attempt.budget.recordingCall()
            do {
                let turn = try await compactionModelTurn(
                    body: body,
                    target: target,
                    incomingHeaders: incomingHeaders,
                    eventID: eventID,
                    attempt: attempt.budget.upstreamCalls,
                    preferredWire: attempt.wire == .chatCompletions ? .chatCompletions : .native)
                attempt.usage.add(turn.usage)
                do {
                    let result = try attempt.plan.complete(
                        responseBody: turn.rootJSON, maximumBytes: maximumRequestBytes)
                    return ResponsesCompactionResult(itemJSON: result.itemJSON, usage: attempt.usage)
                } catch let error as ResponsesCompactionError {
                    guard case .invalidSelection(let reason) = error else { throw error }
                    guard let budget = try? attempt.budget.taking(.selectionRepair) else {
                        throw ResponsesCompactionError.invalidResponse
                    }
                    attempt.budget = budget
                    attempt.repair = reason
                }
            } catch let failure as CompactionUpstreamFailure {
                guard try await retryCompaction(failure, attempt: &attempt, body: body, target: target.route) else {
                    throw failure
                }
            }
        }
    }

    private struct CompactionAttempt {
        var plan: ResponsesCompactionPlan
        var wire: ModelImageInputWire
        var budget = CompactionAttemptBudget()
        var repair: String?
        var usage = ResponsesUsage(inputTokens: 0, outputTokens: 0)
    }

    /// Every retry cause spends the same request-scoped budget. The model-turn executor sends once.
    private func retryCompaction(
        _ failure: CompactionUpstreamFailure,
        attempt: inout CompactionAttempt,
        body: Data,
        target: CodexModelTarget
    ) async throws -> Bool {
        let status = failure.response.status.code
        let routeAbsent =
            attempt.wire == .responses && responsesAdapterFallbackApplies(status: status, provider: target.provider)
        if routeAbsent {
            guard let budget = try? attempt.budget.taking(.routeFallback) else { return false }
            attempt.budget = budget
            attempt.wire = .chatCompletions
            return true
        }
        let hasImages = try !ResponsesImageInputProjection.project(body: body, acceptsImages: true).imageItemIndices
            .isEmpty
        let rejected = await learnResponsesImageRejection(
            status: status, body: failure.body, target: target, wire: attempt.wire, hasImageInput: hasImages)
        if rejected {
            guard let budget = try? attempt.budget.taking(.imageFallback) else { return false }
            attempt.budget = budget
            attempt.plan = try attempt.plan.preservingUninspectedImages()
            return true
        }
        if Self.isContextLimit(failure) {
            guard let budget = try? attempt.budget.taking(.contextTrim), try attempt.plan.trimForContextLimit() > 0
            else { return false }
            attempt.budget = budget
            return true
        }
        return false
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
