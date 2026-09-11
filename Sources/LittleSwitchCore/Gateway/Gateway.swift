import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import LittleSwitchTransport
import NIOCore
import NIOHTTP1

package protocol GatewayAdmitting: Sendable {
    func admit(state: GatewayState, request: GatewayRequestAdmission) async throws
}

package protocol GatewayTokenEstimating: Sendable {
    func estimate(_ request: Data) throws -> Int
    func estimate(root: [String: Any]) throws -> Int
}

package protocol GatewayRoutingSnapshotCapturing: Sendable {
    func capture(state: GatewayState) async throws -> GatewayRoutingCapture
}

package struct LiveGatewayRoutingSnapshotCapturer: GatewayRoutingSnapshotCapturing {
    package init() {}

    package func capture(state: GatewayState) async throws -> GatewayRoutingCapture {
        await state.routingCapture()
    }
}

package struct LiveGatewayTokenEstimator: GatewayTokenEstimating {
    package init() {}

    package func estimate(_ request: Data) throws -> Int {
        try TokenEstimator.estimate(request)
    }

    package func estimate(root: [String: Any]) throws -> Int {
        try TokenEstimator.estimate(root: root)
    }
}

package struct LiveGatewayAdmitter: GatewayAdmitting {
    package init() {}

    package func admit(state: GatewayState, request: GatewayRequestAdmission) async throws {
        try await state.admit(request)
    }
}

package protocol GatewayWebSearchProjecting: Sendable {
    func anthropicResponse(
        prepared: PreparedWebSearchRequest,
        traces: [WebSearchTrace],
        finalTurn: AnthropicModelTurn,
        usage: AnthropicUsage
    ) throws -> Data

    func responsesResponse(
        prepared: PreparedResponsesWebSearchRequest,
        traces: [ResponsesWebSearchTrace],
        finalTurn: ResponsesModelTurn,
        usage: ResponsesUsage
    ) throws -> Data
}

package struct LiveGatewayWebSearchProjector: GatewayWebSearchProjecting {
    package init() {}

    package func anthropicResponse(
        prepared: PreparedWebSearchRequest,
        traces: [WebSearchTrace],
        finalTurn: AnthropicModelTurn,
        usage: AnthropicUsage
    ) throws -> Data {
        if prepared.streaming {
            return try AnthropicWebSearch.streamingResponse(
                originalModel: prepared.originalModel,
                traces: traces,
                finalTurn: finalTurn,
                usage: usage,
                privateToolName: prepared.privateToolName
            )
        }
        return try AnthropicWebSearch.nonStreamingResponse(
            originalModel: prepared.originalModel,
            traces: traces,
            finalTurn: finalTurn,
            usage: usage,
            privateToolName: prepared.privateToolName
        )
    }

    package func responsesResponse(
        prepared: PreparedResponsesWebSearchRequest,
        traces: [ResponsesWebSearchTrace],
        finalTurn: ResponsesModelTurn,
        usage: ResponsesUsage
    ) throws -> Data {
        if prepared.streaming {
            return try OpenAIResponsesWebSearch.streamingResponse(
                prepared: prepared,
                traces: traces,
                finalTurn: finalTurn,
                usage: usage
            )
        }
        return try OpenAIResponsesWebSearch.nonStreamingResponse(
            prepared: prepared,
            traces: traces,
            finalTurn: finalTurn,
            usage: usage
        )
    }
}

public struct GatewayResponder: HTTPResponder {
    public typealias Context = BasicRequestContext

    package enum BodyCollection {
        case data(Data)
        case response(Response)
    }

    package enum ErrorStyle: Sendable {
        case anthropic
        case openAI
    }

    package let state: GatewayState
    package let transport: any UpstreamTransport
    package let secretStore: any SecretStore
    package let maximumRequestBytes: Int
    package let maximumErrorBytes: Int
    private let authorityPolicy: GatewayAuthorityPolicy
    package var trafficRecorder: any TrafficRecording
    package let monitoring: GatewayMonitoring?
    package let dependencies: GatewayResponderDependencies

    public init(
        state: GatewayState,
        transport: any UpstreamTransport,
        secretStore: any SecretStore,
        maximumRequestBytes: Int = 64 * 1_024 * 1_024,
        maximumErrorBytes: Int = 8 * 1_024 * 1_024,
        requiredAuthorityPort: Int? = 11_436,
        trafficRecorder: any TrafficRecording = NoopTrafficRecorder(),
        monitoring: GatewayMonitoring? = nil
    ) {
        self.init(
            state: state,
            transport: transport,
            secretStore: secretStore,
            maximumRequestBytes: maximumRequestBytes,
            maximumErrorBytes: maximumErrorBytes,
            requiredAuthorityPort: requiredAuthorityPort,
            trafficRecorder: trafficRecorder,
            monitoring: monitoring,
            dependencies: GatewayResponderDependencies()
        )
    }

    package init(
        state: GatewayState,
        transport: any UpstreamTransport,
        secretStore: any SecretStore,
        maximumRequestBytes: Int = 64 * 1_024 * 1_024,
        maximumErrorBytes: Int = 8 * 1_024 * 1_024,
        requiredAuthorityPort: Int? = 11_436,
        trafficRecorder: any TrafficRecording = NoopTrafficRecorder(),
        monitoring: GatewayMonitoring? = nil,
        dependencies: GatewayResponderDependencies
    ) {
        self.state = state
        self.transport = transport
        self.secretStore = secretStore
        self.maximumRequestBytes = maximumRequestBytes
        self.maximumErrorBytes = maximumErrorBytes
        self.authorityPolicy = GatewayAuthorityPolicy(requiredAuthorityPort)
        self.trafficRecorder = trafficRecorder
        self.monitoring = monitoring
        self.dependencies = dependencies
    }

    package func routeResponse(_ request: Request, eventID: UUID) async throws -> Response {
        let resolvedPath = GatewayRoute.resolve(request.uri.path)
        let path = resolvedPath
        let errorStyle: ErrorStyle = path == .responses ? .openAI : .anthropic
        guard request.headers[.origin] == nil else {
            return errorResponse(
                style: errorStyle,
                status: .forbidden,
                message: "Origin requests are not allowed"
            )
        }
        guard let authority = request.head.authority,
            authorityPolicy.allows(authority)
        else {
            return errorResponse(
                style: errorStyle,
                status: .forbidden,
                message: "Loopback Host is required"
            )
        }
        guard let path else {
            return anthropicError(status: .notFound, message: "Unknown endpoint")
        }
        guard path == .metrics || path == .logs || path.accepts(method: request.method) else {
            // Codex's native provider streams each turn over a websocket
            // first and only falls back to HTTP SSE when the upgrade fails
            // with 426 Upgrade Required. Any other status — including the
            // router's default 405 — reads as a retryable stream error, so
            // the turn exhausts its retries on the websocket and dies.
            if path == .responses, requestsWebsocketUpgrade(request) {
                var headers = HTTPFields()
                headers[.upgrade] = "websocket"
                return errorResponse(
                    style: errorStyle,
                    status: .upgradeRequired,
                    message: "WebSockets are not supported; stream over HTTP",
                    headers: headers
                )
            }
            var headers = HTTPFields()
            headers[.allow] = path.method.rawValue
            return errorResponse(
                style: errorStyle,
                status: .methodNotAllowed,
                message: "Method not allowed",
                headers: headers
            )
        }
        switch path {
        case .health:
            var headers = HTTPFields()
            if let marker = HTTPField.Name("X-LittleSwitch-Claude-Gateway") {
                headers[marker] = "1"
            }
            return Response(status: .noContent, headers: headers)
        case .about:
            return aboutResponse()
        case .hello:
            return helloResponse()
        case .managedWebSearch:
            return try await managedWebSearchResponse(request, eventID: eventID)
        case .webSearchMCP:
            return try await webSearchMCPResponse(request, eventID: eventID)
        case .models:
            return try await modelsResponse()
        case .countTokens:
            return try await countTokensResponse(request, eventID: eventID)
        case .messages:
            return try await messagesResponse(request, eventID: eventID)
        case .responses:
            return try await responsesResponse(request, eventID: eventID)
        case .metrics, .logs:
            return try await monitoringResponse(request, route: path)
        }
    }

    /// A websocket handshake the gateway cannot satisfy: the client asked
    /// to switch protocols rather than merely using the wrong method. The
    /// transport layer keeps the Connection header consistent with the
    /// Upgrade token, so the token alone identifies the handshake.
    private func requestsWebsocketUpgrade(_ request: Request) -> Bool {
        guard let upgrade = request.headers[.upgrade] else {
            return false
        }
        return upgrade.caseInsensitiveCompare("websocket") == .orderedSame
    }

    private func countTokensResponse(_ request: Request, eventID: UUID) async throws -> Response {
        try Task.checkCancellation()
        let capture = try await dependencies.snapshotCapturer.capture(state: state)
        try Task.checkCancellation()
        let body: Data
        switch try await collect(request.body, errorStyle: .anthropic) {
        case .data(let value):
            body = value
        case .response(let response):
            return response
        }
        trafficRecorder.record(eventID: eventID, action: .claudeRequestBody(body))
        let root: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                throw TokenEstimator.Error.invalidRoot
            }
            root = object
        } catch {
            return anthropicError(status: .badRequest, message: "Invalid token count request")
        }
        guard
            let model = root["model"] as? String,
            let target = capture.snapshot.resolve(model: model)
        else {
            return anthropicError(status: .badRequest, message: "Unknown or invalid model mapping")
        }
        await GatewayMonitoringScope.current?.target(providerID: target.provider.id, model: target.modelID)
        do {
            let estimate = try dependencies.tokenEstimator.estimate(root: root)
            await GatewayMonitoringScope.current?.estimatedInput(estimate)
            let data = try JSONSerialization.data(
                withJSONObject: ["input_tokens": estimate],
                options: [.sortedKeys]
            )
            return jsonResponse(status: .ok, data: data)
        } catch {
            return anthropicError(status: .badRequest, message: "Invalid token count request")
        }
    }

    package func collect(
        _ body: RequestBody,
        errorStyle: ErrorStyle
    ) async throws -> BodyCollection {
        try Task.checkCancellation()
        do {
            let buffer = try await body.collect(upTo: maximumRequestBytes)
            try Task.checkCancellation()
            return .data(Data(buffer.readableBytesView))
        } catch is CancellationError {
            throw CancellationError()
        } catch is NIOTooManyBytesError {
            return .response(
                errorResponse(
                    style: errorStyle,
                    status: .contentTooLarge,
                    message: "Request body is too large"
                )
            )
        } catch {
            return .response(
                errorResponse(
                    style: errorStyle,
                    status: .badRequest,
                    message: "Could not read request body"
                )
            )
        }
    }

    package func errorResponse(
        style: ErrorStyle,
        status: HTTPResponse.Status,
        message: String,
        headers: HTTPFields = [:]
    ) -> Response {
        switch style {
        case .anthropic:
            anthropicError(status: status, message: message, headers: headers)
        case .openAI:
            openAIError(status: status, message: message, headers: headers)
        }
    }

}

package func nioHeaders(_ fields: HTTPFields) -> HTTPHeaders {
    var headers = HTTPHeaders()
    for field in fields {
        headers.add(name: field.name.rawName, value: field.value)
    }
    return headers
}

package func jsonResponse(status: HTTPResponse.Status, data: Data) -> Response {
    Response(
        status: status,
        headers: [.contentType: "application/json"],
        body: ResponseBody(byteBuffer: ByteBuffer(bytes: data))
    )
}

package func anthropicError(
    status: HTTPResponse.Status,
    message: String,
    headers: HTTPFields = [:]
) -> Response {
    anthropicError(
        status: status,
        message: message,
        errorType: "invalid_request_error",
        headers: headers
    )
}

package func anthropicError(
    status: HTTPResponse.Status,
    message: String,
    errorType: String,
    headers: HTTPFields = [:]
) -> Response {
    let object: [String: Any] = [
        "type": "error",
        "error": [
            "type": errorType,
            "message": message,
        ],
    ]
    let data = safeGatewayJSONData(object)
    var responseHeaders = headers
    responseHeaders[.contentType] = "application/json"
    return Response(
        status: status,
        headers: responseHeaders,
        body: ResponseBody(byteBuffer: ByteBuffer(bytes: data))
    )
}

package func openAIError(
    status: HTTPResponse.Status,
    message: String,
    headers: HTTPFields = [:]
) -> Response {
    openAIError(
        status: status,
        message: message,
        errorType: "invalid_request_error",
        headers: headers
    )
}

package func openAIError(
    status: HTTPResponse.Status,
    message: String,
    errorType: String,
    headers: HTTPFields = [:]
) -> Response {
    let object: [String: Any] = [
        "error": [
            "message": message,
            "type": errorType,
            "param": NSNull(),
            "code": NSNull(),
        ]
    ]
    let data = safeGatewayJSONData(object)
    var responseHeaders = headers
    responseHeaders[.contentType] = "application/json"
    return Response(
        status: status,
        headers: responseHeaders,
        body: ResponseBody(byteBuffer: ByteBuffer(bytes: data))
    )
}

package func safeGatewayJSONData(
    _ object: Any,
    serializer: any GatewaySerializing = LiveGatewaySerializer()
) -> Data {
    guard JSONSerialization.isValidJSONObject(object) else {
        return Data()
    }
    do {
        return try serializer.encodeJSONObject(object)
    } catch {
        return Data()
    }
}
