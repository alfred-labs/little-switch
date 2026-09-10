import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import NIOCore
import NIOHTTP1

@testable import LittleSwitchSearch

struct RecordedSearchRequest: Sendable {
    let url: String
    let method: HTTPMethod
    let headers: HTTPHeaders
    let body: Data
}

actor SearchRecordingTransport: UpstreamTransport {
    private(set) var requests: [RecordedSearchRequest] = []
    private var responses: [HTTPClientResponse]

    init(responses: [HTTPClientResponse]) {
        self.responses = responses
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        let body = try await recordedBody(request.body)
        requests.append(
            RecordedSearchRequest(
                url: request.url,
                method: request.method,
                headers: request.headers,
                body: body
            )
        )
        return responses.removeFirst()
    }
}

actor SearchFailingTransport: UpstreamTransport {
    enum Failure: Sendable {
        case unavailable
        case cancelled
    }

    let error: Failure

    init(error: Failure) {
        self.error = error
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        _ = request
        switch error {
        case .unavailable:
            throw URLError(.cannotConnectToHost)
        case .cancelled:
            throw CancellationError()
        }
    }
}

func searchResponse(
    status: HTTPResponseStatus = .ok,
    body: String
) -> HTTPClientResponse {
    HTTPClientResponse(
        status: status,
        headers: ["content-type": "application/json"],
        body: .bytes(ByteBuffer(string: body))
    )
}

struct SearchResponseStreamError: Swift.Error {}

func searchFailingResponse(error: any Swift.Error) -> HTTPClientResponse {
    let stream = AsyncThrowingStream<ByteBuffer, any Swift.Error> { continuation in
        continuation.finish(throwing: error)
    }
    return HTTPClientResponse(status: .ok, body: .stream(stream))
}
