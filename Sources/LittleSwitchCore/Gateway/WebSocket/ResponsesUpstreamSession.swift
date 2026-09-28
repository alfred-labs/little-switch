import AsyncAlgorithms
import AsyncHTTPClient
import Foundation
import HTTPTypes
import LittleSwitchCommon
import LittleSwitchTransport
import LittleSwitchWire
import NIOHTTP1

/// A local provider revision binds a socket to its admitted credential/settings.
package struct ResponsesUpstreamProvider: Equatable, Sendable {
    let id: UUID
    let revision: UInt64
}

/// Session keys contain local identities and configuration, never credentials.
package struct ResponsesUpstreamKey: Equatable, Sendable {
    let provider: ResponsesUpstreamProvider?
    let endpoint: String
    let model: String
}

package struct ResponsesUpstreamPolicy: Sendable {
    let provider: ResponsesUpstreamProvider?
    let observeControl: @Sendable (String) -> Void
    let validateProvider: @Sendable () async throws -> Void
}

package struct ResponsesWebSocketExchangeContext: Sendable {
    private typealias ResponseKey = OpenAIResponsesResponse.Key
    private typealias RoutingKey = OpenAIResponsesRoutingRequest.Key
    let session: ResponsesUpstreamSession
    let turn: ResponsesWebSocketTurn

    func execute(
        request: HTTPClientRequest,
        body: Data,
        provider: ResponsesUpstreamProvider? = nil,
        observeControl: @escaping @Sendable (String) -> Void = { _ in },
        validateProvider: @escaping @Sendable () async throws -> Void = {}
    ) async throws -> HTTPClientResponse? {
        let nativeResponse = try await session.exchange(
            turn: turn,
            request: request,
            body: body,
            policy: .init(provider: provider, observeControl: observeControl, validateProvider: validateProvider))
        if let nativeResponse { return nativeResponse }
        return turn.generate ? nil : try Self.warmup(body: body)
    }

    static func warmup(body: Data) throws -> HTTPClientResponse {
        let response: JSONValue = [
            ResponseKey.id.rawValue: .string(
                "resp_ls_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()),
            ResponseKey.object.rawValue: .string(OpenAIResponsesResponseObject.response.rawValue),
            ResponseKey.status.rawValue: .string(OpenAIResponsesStatus.completed.rawValue),
            ResponseKey.output.rawValue: [],
            RoutingKey.model.rawValue: try JSONValue.parse(body).object?[RoutingKey.model.rawValue] ?? .null,
        ]
        return HTTPClientResponse(
            status: .ok,
            headers: [HTTPField.Name.contentType.rawName: "application/json"],
            body: .bytes(.init(bytes: try response.serializedData())))
    }

    func requireFallbackAllowed() async throws {
        try await session.requireFallbackAllowed(turn)
    }
}

/// The incoming socket's task group owns run(). Each connection operation is
/// its structured child, so downstream cancellation joins every upstream scope.
package actor ResponsesUpstreamSession {
    private typealias EventKey = OpenAIResponsesCreatedEvent.Key
    private typealias InputKey = OpenAIResponsesRequestEnvelope.Key
    private typealias RoutingKey = OpenAIResponsesRoutingRequest.Key
    private typealias RequestField = ResponsesWebSocketContract.RequestField
    private let transport: any UpstreamWebSocketTransport
    private let limits: ResponsesWebSocketLimits
    private let control: @Sendable (Data) async throws -> Void
    private let openings = AsyncChannel<ResponsesUpstreamConnection>()
    private var lanes: [String: ResponsesUpstreamConnection] = [:]
    private var turns: [UUID: ResponsesUpstreamConnection] = [:]
    private var unsupported: Set<String> = []

    package init(
        transport: any UpstreamWebSocketTransport,
        limits: ResponsesWebSocketLimits,
        control: @escaping @Sendable (Data) async throws -> Void
    ) {
        self.transport = transport
        self.limits = limits
        self.control = control
    }

    package func run() async {
        await withDiscardingTaskGroup { group in
            for await connection in openings {
                group.addTask { [transport] in await connection.run(transport: transport) }
            }
            group.cancelAll()
        }
    }

    package func finish() {
        openings.finish()
    }

    package func usesNative(_ turnID: UUID) -> Bool { turns[turnID] != nil }

    package func release(_ turnID: UUID) { turns.removeValue(forKey: turnID) }

    package func abort(_ turnID: UUID) async {
        if let connection = turns.removeValue(forKey: turnID) { await connection.close() }
    }

    package func appliedInput(turnID: UUID, responseID: String) async -> [JSONValue] {
        await turns[turnID]?.takeAppliedInput(responseID: responseID) ?? []
    }

    package func requireFallbackAllowed(_ turn: ResponsesWebSocketTurn) async throws {
        if let connection = lanes[turn.streamID ?? ""], await connection.usable, await connection.hasPendingSteering {
            throw ResponsesWebSocketFailure(
                status: 409,
                code: "pending_steering",
                message: "Resolve pending steering on its original native connection."
                    + " Reconnect with complete portable history and explicitly resubmit unapplied steering if that provider is no longer valid."
            )
        }
    }

    package func steer(_ steering: ResponsesWebSocketSteering) async throws {
        var owner: ResponsesUpstreamConnection?
        for connection in lanes.values where await connection.owns(steering.previousResponseID) {
            guard owner == nil else {
                throw ResponsesWebSocketFailure(
                    status: 400, code: "response_not_found", message: "The response identifier is ambiguous")
            }
            owner = connection
        }
        if let owner {
            try await owner.steer(steering)
            return
        }
        throw ResponsesWebSocketFailure(
            status: 400, code: "steering_not_supported", message: "The response has no compatible native connection")
    }

    package func exchange(
        turn: ResponsesWebSocketTurn,
        request: HTTPClientRequest,
        body: Data,
        policy: ResponsesUpstreamPolicy
    ) async throws -> HTTPClientResponse? {
        try Task.checkCancellation()
        guard var fields = try JSONValue.parse(body).object,
            let model = fields[RoutingKey.model.rawValue]?.string
        else { throw ResponsesWebSocketEvents.Error.invalidEvent }
        let key = ResponsesUpstreamKey(
            provider: policy.provider,
            endpoint: request.url,
            model: model)
        let laneID = turn.streamID ?? ""
        let endpointKey = request.url
        guard !unsupported.contains(endpointKey) else { return nil }
        let connection: ResponsesUpstreamConnection
        if let existing = lanes[laneID], existing.key == key, await existing.usable {
            connection = existing
        } else {
            if let old = lanes[laneID], await old.usable, await old.hasPendingSteering {
                let providerChanged =
                    old.key.provider != key.provider || old.key.endpoint != key.endpoint
                throw ResponsesWebSocketFailure(
                    status: 409,
                    code: "pending_steering",
                    message: providerChanged
                        ? "The pending response provider changed. Reconnect, replay complete portable history, and explicitly resubmit unapplied steering."
                        : "Resolve pending steering on the original model before changing the upstream chain")
            }
            if let old = lanes.removeValue(forKey: laneID) { await old.close() }
            let upgrade = try Self.upgrade(request)
            connection = ResponsesUpstreamConnection(
                key: key, request: upgrade, maximumBytes: limits.maxResponseBytes, control: control)
            lanes[laneID] = connection
            await openings.send(connection)
        }
        fields[EventKey.type.rawValue] = .string(ResponsesWebSocketContract.Event.create.rawValue)
        fields[RequestField.stream.rawValue] = nil
        fields[RequestField.previousResponseID.rawValue] = nil
        fields[RequestField.generate.rawValue] = turn.generate ? nil : .boolean(false)
        // Reuse only a verified suffix. Projection may expand/filter input, in
        // which case a full portable replay is safer than counting raw items.
        let delta = try turn.incrementalInput.flatMap { try JSONValue.parse($0).array }
        let safeDelta = delta.flatMap { Self.endsWith(fields[InputKey.input.rawValue]?.array, delta: $0) ? $0 : nil }
        if let previous = turn.previousResponseID, await connection.canContinue(previous), let delta = safeDelta {
            fields[RequestField.previousResponseID.rawValue] = .string(previous)
            fields[InputKey.input.rawValue] = .array(delta)
        }
        do {
            let response = try await connection.exchange(
                JSONValue.object(fields).serializedData(),
                previousResponseID: fields[RequestField.previousResponseID.rawValue]?.string,
                observeControl: policy.observeControl,
                validateProvider: policy.validateProvider)
            turns[turn.id] = connection
            return response
        } catch let failure as UpstreamWebSocketFailure where failure.kind == .upgradeRejected {
            // The HTTP upgrade sent no model request. Only an explicit lack of
            // WS support falls back; auth/rate errors keep their original cause.
            if let status = failure.response?.head.status.code, [400, 404, 405, 426, 501].contains(status) {
                unsupported.insert(endpointKey)
                lanes.removeValue(forKey: laneID)
                return nil
            }
            if let rejected = failure.response {
                return HTTPClientResponse(
                    status: rejected.head.status,
                    headers: rejected.head.headers,
                    body: .bytes(.init(bytes: rejected.bodyPrefix)))
            }
            throw failure
        }
    }

    private static func endsWith(_ full: [JSONValue]?, delta: [JSONValue]) -> Bool {
        guard let full, full.count >= delta.count else { return false }
        return Array(full.suffix(delta.count)) == delta
    }

    private static func upgrade(_ request: HTTPClientRequest) throws -> UpstreamWebSocketRequest {
        guard var url = URLComponents(string: request.url), ["http", "https"].contains(url.scheme ?? "") else {
            throw UpstreamWebSocketFailure(kind: .invalidRequest)
        }
        url.scheme = url.scheme == "https" ? "wss" : "ws"
        guard let address = url.url else { throw UpstreamWebSocketFailure(kind: .invalidRequest) }
        var headers = request.headers
        for name in [
            "host", "connection", "upgrade", "content-length", HTTPField.Name.contentType.rawName, "accept",
            "transfer-encoding", "content-encoding", "sec-websocket-key", "sec-websocket-version",
            "sec-websocket-protocol", "sec-websocket-extensions",
        ] { headers.remove(name: name) }
        return try UpstreamWebSocketRequest(url: address, headers: headers)
    }
}
