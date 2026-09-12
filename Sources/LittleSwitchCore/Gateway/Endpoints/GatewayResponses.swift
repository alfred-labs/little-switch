import AsyncHTTPClient
import Foundation
import Hummingbird
import LittleSwitchTransport
import NIOHTTP1

package struct TransparentResponsesContext {
    let body: Data
    let model: String
    let target: CodexModelTarget
    let credential: String?
    let incomingHeaders: HTTPHeaders
    let eventID: UUID
    let streaming: Bool

    package init(
        body: Data,
        model: String,
        target: CodexModelTarget,
        credential: String?,
        incomingHeaders: HTTPHeaders,
        eventID: UUID,
        streaming: Bool
    ) {
        self.body = body
        self.model = model
        self.target = target
        self.credential = credential
        self.incomingHeaders = incomingHeaders
        self.eventID = eventID
        self.streaming = streaming
    }
}

private struct ResponsesRoutingMetadata {
    let model: String
    let target: CodexModelTarget
    let streaming: Bool
}

extension GatewayResponder {
    package func responsesResponse(
        _ request: Request,
        eventID: UUID
    ) async throws -> Response {
        try Task.checkCancellation()
        let capture = try await dependencies.snapshotCapturer.capture(state: state)
        try Task.checkCancellation()
        let incomingBody: Data
        switch try await collectDecodedResponsesBody(request) {
        case .data(let body):
            incomingBody = body
        case .response(let response):
            return response
        }

        trafficRecorder.record(eventID: eventID, action: .claudeRequestBody(incomingBody))
        let incomingHeaders = nioHeaders(request.headers)
        guard let metadata = responsesRoutingMetadata(body: incomingBody, capture: capture) else {
            if CodexNativePassthrough.isNativeRequest(incomingBody) {
                return try await nativeResponsesResponse(
                    body: incomingBody, incomingHeaders: incomingHeaders, eventID: eventID
                )
            }
            return openAIError(status: .badRequest, message: "Unknown or invalid model")
        }
        await GatewayMonitoringScope.current?.target(
            providerID: metadata.target.provider.id, model: metadata.target.model.id)
        let prepared: PreparedGatewayResponses
        do {
            // Foreign checkpoints cannot be read by any provider: degrade them
            // the way Ollama's proxy omits foreign compaction state on
            // provider switches, then admit the readable history.
            let degraded = try ResponsesProviderState.degradedBody(incomingBody)
            prepared = try PreparedGatewayResponses(
                body: degraded, target: metadata.target, configuration: capture.snapshot.webSearch)
        } catch {
            return openAIError(status: .badRequest, message: "Invalid Responses request")
        }
        let secret: String?
        do {
            secret = try await state.providerCredential(
                providerID: metadata.target.provider.id,
                capture: capture,
                secretStore: secretStore
            )
        } catch GatewayAdmissionError.invalidated {
            await GatewayMonitoringScope.current?.admission(.invalidated)
            throw HandledAdmissionFailure(style: .openAI, kind: .queue)
        } catch {
            return openAIError(
                status: .internalServerError,
                message: "Could not read provider credential"
            )
        }

        trafficRecorder.record(
            eventID: eventID,
            action: .routed(
                trafficRoute(
                    client: .codex,
                    modelIdentifier: metadata.model,
                    target: metadata.target,
                    streaming: metadata.streaming
                )
            )
        )
        try await admitRequest(
            GatewayRequestAdmission(
                eventID: eventID,
                capture: capture,
                client: .codex,
                modelIdentifier: metadata.model,
                providerID: metadata.target.provider.id,
                targetModelID: metadata.target.model.id,
                retainedBodyBytes: incomingBody.count
            ),
            errorStyle: .openAI
        )
        try Task.checkCancellation()
        return try await admittedResponsesResponse(
            TransparentResponsesContext(
                body: incomingBody,
                model: metadata.model,
                target: metadata.target,
                credential: secret,
                incomingHeaders: incomingHeaders,
                eventID: eventID,
                streaming: metadata.streaming
            ),
            prepared: prepared,
            configuration: capture.snapshot.webSearch
        )
    }

    package func transparentResponsesResponse(
        _ context: TransparentResponsesContext
    ) async throws -> Response {
        let needsChatCompletionsAdapter = await resolvesChatCompletionsAdapter(
            context.target.provider
        )
        if needsChatCompletionsAdapter {
            return try await chatCompletionsResponsesResponse(context)
        }
        let upstreamBody: Data
        let normalized: OpenAIResponsesNativeNamespacing.Normalized
        do {
            let rewritten = try dependencies.serializer.rewriteResponses(
                context.body,
                modelID: context.target.model.id
            )
            // Admission already routes owned history through its adapter.
            // Native image turns still need an explicit completion budget.
            normalized = try OpenAIResponsesNativeNamespacing.normalize(rewritten)
            upstreamBody = try ResponsesChatCompletionsReasoning.nativeRequestBody(
                normalized.body, providerID: context.target.provider.id)
        } catch {
            return openAIError(status: .badRequest, message: "Invalid Responses request")
        }
        let upstreamRequest: HTTPClientRequest
        do {
            upstreamRequest = try ProviderRequestBuilder.responses(
                provider: context.target.provider,
                secret: context.credential,
                headers: context.incomingHeaders,
                body: upstreamBody
            )
        } catch {
            return openAIError(status: .serviceUnavailable, message: "Provider is not ready")
        }
        try Task.checkCancellation()

        trafficRecorder.record(
            eventID: context.eventID,
            action: .upstreamRequest(
                trafficUpstreamRequest(
                    attempt: 0,
                    route: ResponsesTrafficRoute(
                        claudeRoute: context.model,
                        target: context.target
                    ),
                    request: upstreamRequest,
                    body: upstreamBody,
                    streaming: context.streaming
                )
            )
        )

        let exchange: GatewayModelExchange
        do {
            try Task.checkCancellation()
            exchange = try await executeModelRequest(
                upstreamRequest,
                body: upstreamBody,
                wire: .responses,
                eventID: context.eventID,
                attempt: 0,
                declaredToolBindings: normalized.declaredToolBindings,
                toolNameCatalog: normalized.toolNameCatalog
            )
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return openAIError(status: .badGateway, message: "Provider request failed")
        }
        let upstreamResponse = exchange.response
        await recordResponsesCapability(
            providerID: context.target.provider.id,
            status: UInt(upstreamResponse.status.code)
        )
        if responsesAdapterFallbackApplies(
            status: UInt(upstreamResponse.status.code),
            provider: context.target.provider
        ) {
            // Consume the small error body so the pooled connection survives
            // for the adapter retry to the same host.
            _ = try? await exchange.trace.collect(upstreamResponse.body, upTo: 16 * 1_024)
            // First contact with a chat-completions-only provider: the learned
            // verdict now routes it through the adapter, so this request still
            // succeeds instead of surfacing the provider's 404. Providers
            // pinned to a wire relay the failure instead. The retry records
            // under its own attempt so the traffic log keeps both exchanges.
            return try await chatCompletionsResponsesResponse(context, attempt: 1)
        }
        return streamingResponse(
            upstreamResponse, eventID: context.eventID, attempt: 0, errorStyle: .openAI, trace: exchange.trace)
    }

    private enum ResponsesBodyError: Swift.Error {
        case unsupportedContentEncoding
    }

    private func collectDecodedResponsesBody(_ request: Request) async throws -> BodyCollection {
        switch try await collect(request.body, errorStyle: .openAI) {
        case .data(let compressedBody):
            do {
                return .data(
                    try decodedResponsesBody(
                        compressedBody,
                        contentEncoding: request.headers[.contentEncoding]
                    )
                )
            } catch Zstandard.Error.outputTooLarge {
                return .response(
                    openAIError(
                        status: .contentTooLarge,
                        message: "Expanded request body is too large"
                    )
                )
            } catch Zstandard.Error.invalidFrame {
                return .response(
                    openAIError(status: .badRequest, message: "Invalid zstd request body")
                )
            } catch ResponsesBodyError.unsupportedContentEncoding {
                return .response(
                    openAIError(
                        status: .unsupportedMediaType,
                        message: "Unsupported request content encoding"
                    )
                )
            }
        case .response(let response):
            return .response(response)
        }
    }

    private func decodedResponsesBody(
        _ body: Data,
        contentEncoding: String?
    ) throws -> Data {
        let encodings = (contentEncoding ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && $0 != "identity" }
        guard !encodings.isEmpty else {
            return body
        }
        guard encodings == ["zstd"] else {
            throw ResponsesBodyError.unsupportedContentEncoding
        }
        return try Zstandard.decompress(body, maximumOutputBytes: maximumRequestBytes)
    }

    private func responsesRoutingMetadata(
        body: Data,
        capture: GatewayRoutingCapture
    ) -> ResponsesRoutingMetadata? {
        guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let model = root["model"] as? String,
            let target = capture.snapshot.resolveCodex(model: model)
        else {
            return nil
        }
        return ResponsesRoutingMetadata(
            model: model,
            target: target,
            streaming: root["stream"] as? Bool ?? false
        )
    }
}
