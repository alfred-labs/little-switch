import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import NIOCore
import NIOHTTP1

@testable import LittleSwitchCore

struct FailingGatewaySerializer: GatewaySerializing {
    func encodeJSONObject(_ object: Any) throws -> Data {
        _ = object
        throw GatewayTestError.privateFailure
    }

    func encodeCatalog(_ response: ClaudeCatalogResponse) throws -> Data {
        _ = response
        throw GatewayTestError.failure
    }

    func rewriteMessage(_ body: Data, modelID: String) throws -> Data {
        _ = body
        _ = modelID
        throw GatewayTestError.failure
    }

    func rewriteResponses(_ body: Data, modelID: String) throws -> Data {
        _ = body
        _ = modelID
        throw GatewayTestError.failure
    }
}

struct FailingGatewayWebSearchProjector: GatewayWebSearchProjecting {
    func anthropicResponse(
        prepared: PreparedWebSearchRequest,
        traces: [WebSearchTrace],
        finalTurn: AnthropicModelTurn,
        usage: AnthropicUsage
    ) throws -> Data {
        _ = prepared
        _ = traces
        _ = finalTurn
        _ = usage
        throw GatewayTestError.failure
    }

    func responsesResponse(
        prepared: PreparedResponsesWebSearchRequest,
        traces: [ResponsesWebSearchTrace],
        finalTurn: ResponsesModelTurn,
        usage: ResponsesUsage
    ) throws -> Data {
        _ = prepared
        _ = traces
        _ = finalTurn
        _ = usage
        throw GatewayTestError.failure
    }
}

struct FailingGatewayTokenEstimator: GatewayTokenEstimating {
    func estimate(_ request: Data) throws -> Int {
        _ = request
        throw GatewayTestError.failure
    }

    func estimate(root: [String: Any]) throws -> Int {
        _ = root
        throw GatewayTestError.failure
    }
}

struct FailingGatewayBodySequence: AsyncSequence, Sendable {
    typealias Element = ByteBuffer

    struct AsyncIterator: AsyncIteratorProtocol {
        mutating func next() async throws -> ByteBuffer? {
            throw GatewayTestError.failure
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator()
    }
}

struct CancellingGatewayBodySequence: AsyncSequence, Sendable {
    typealias Element = ByteBuffer

    struct AsyncIterator: AsyncIteratorProtocol {
        mutating func next() async throws -> ByteBuffer? {
            throw CancellationError()
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator()
    }
}

struct ThrowingGatewaySecretStore: SecretStore {
    func read(account: SecretAccount) throws -> String? {
        _ = account
        throw GatewayTestError.privateFailure
    }

    func write(_ secret: String, account: SecretAccount) throws {
        _ = secret
        _ = account
        throw GatewayTestError.failure
    }

    func delete(account: SecretAccount) throws {
        _ = account
        throw GatewayTestError.failure
    }
}

struct SearchThrowingGatewaySecretStore: SecretStore {
    let providerID: UUID
    let providerSecret: String

    func read(account: SecretAccount) throws -> String? {
        switch account {
        case .provider(let id) where id == providerID:
            providerSecret
        case .webSearch:
            throw GatewayTestError.privateFailure
        default:
            nil
        }
    }

    func write(_ secret: String, account: SecretAccount) throws {
        _ = secret
        _ = account
    }

    func delete(account: SecretAccount) throws {
        _ = account
    }
}

enum GatewayTestError: Swift.Error, Equatable {
    case failure
    case privateFailure
}

actor FailingGatewayTransport: UpstreamTransport {
    let error: GatewayTestError

    init(error: GatewayTestError) {
        self.error = error
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        _ = request
        throw error
    }
}

enum GatewayTransportStep: Sendable {
    case response(HTTPClientResponse)
    case failure(GatewayTestError)
    case cancellation
}

actor SteppingGatewayTransport: UpstreamTransport {
    private var steps: [GatewayTransportStep]
    private(set) var requests: [RecordedGatewayRequest] = []

    init(steps: [GatewayTransportStep]) {
        self.steps = steps
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        var body = Data()
        if let requestBody = request.body {
            for try await buffer in requestBody {
                body.append(contentsOf: buffer.readableBytesView)
            }
        }
        requests.append(RecordedGatewayRequest(url: request.url, headers: request.headers, body: body))
        guard !steps.isEmpty else {
            throw GatewayTestError.failure
        }
        switch steps.removeFirst() {
        case .response(let response):
            return response
        case .failure(let error):
            throw error
        case .cancellation:
            throw CancellationError()
        }
    }
}

func failingResponse(
    status: HTTPResponseStatus = .ok,
    error: any Swift.Error
) -> HTTPClientResponse {
    let stream = AsyncThrowingStream<ByteBuffer, any Swift.Error> { continuation in
        continuation.finish(throwing: error)
    }
    return HTTPClientResponse(status: status, body: .stream(stream))
}
