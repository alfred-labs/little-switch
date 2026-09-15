import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import NIOCore
import NIOHTTP1

@testable import LittleSwitchCore

enum CustomCapabilityProbeStep: Sendable {
    case echo
    case noCall
    case wrongMarker
    case invalidEnvelope
    case incomplete
    case http(CustomCapabilityHTTPFixture)
    case oversized
    case transportFailure
    case cancellation

    static func http(_ status: Int, _ body: String) -> Self {
        .http(CustomCapabilityHTTPFixture(status: status, body: body))
    }
}

struct CustomCapabilityHTTPFixture: Sendable, Equatable {
    let status: Int
    let body: String
}

actor CustomCapabilityProbeTransport: UpstreamTransport {
    private var steps: [CustomCapabilityProbeStep]
    private(set) var requests: [RecordedGatewayRequest] = []
    private(set) var timeouts: [TimeAmount] = []

    init(_ steps: [CustomCapabilityProbeStep]) { self.steps = steps }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        try await execute(request, timeout: .seconds(0))
    }

    func execute(_ request: HTTPClientRequest, timeout: TimeAmount) async throws -> HTTPClientResponse {
        var body = Data()
        if let requestBody = request.body {
            for try await buffer in requestBody { body.append(contentsOf: buffer.readableBytesView) }
        }
        requests.append(RecordedGatewayRequest(url: request.url, headers: request.headers, body: body))
        timeouts.append(timeout)
        guard !steps.isEmpty else { throw URLError(.unknown) }
        let step = steps.removeFirst()
        switch step {
        case .transportFailure: throw URLError(.timedOut)
        case .cancellation: throw CancellationError()
        case .http(let fixture):
            return response(status: HTTPResponseStatus(statusCode: fixture.status), body: fixture.body)
        case .oversized: return response(status: .ok, body: String(repeating: "x", count: 65_537))
        default: break
        }
        let root = try WireJSONCompatibility.fields(body)
        let isResponses = root["input"] != nil
        let messages = root[isResponses ? "input" : "messages"] as? [[String: Any]] ?? []
        let prompt = messages.first?["content"] as? String ?? ""
        let marker = prompt.components(separatedBy: "\n").last ?? ""
        let declaration = (root["tools"] as? [[String: Any]])?.first ?? [:]
        let isCustom = declaration["type"] as? String == "custom"
        let value = step == .wrongMarker ? "incorrect-marker" : marker
        let arguments = step == .invalidEnvelope ? "{\"input\":1}" : "{\"input\":\"\(value)\"}"
        let name = "littleswitch_custom_probe"
        let call: [String: Any]
        if isResponses {
            call = [
                "id": "probe_item", "call_id": "probe_call", "status": "completed", "name": name,
                "type": isCustom ? "custom_tool_call" : "function_call",
                isCustom ? "input" : "arguments": isCustom ? value : arguments,
            ]
        } else {
            call = [
                "id": "probe_call", "type": isCustom ? "custom" : "function",
                isCustom ? "custom" : "function": [
                    "name": name, isCustom ? "input" : "arguments": isCustom ? value : arguments,
                ],
            ]
        }
        let result: [String: Any]
        if isResponses {
            result = [
                "status": step == .incomplete ? "incomplete" : "completed", "output": step == .noCall ? [] : [call],
            ]
        } else {
            let reason = step == .incomplete ? "length" : step == .noCall ? "stop" : "tool_calls"
            result = [
                "choices": [
                    [
                        "finish_reason": reason,
                        "message": [
                            "role": "assistant", "content": NSNull(), "tool_calls": step == .noCall ? [] : [call],
                        ],
                    ]
                ]
            ]
        }
        return HTTPClientResponse(
            status: .ok, headers: [:], body: .bytes(ByteBuffer(bytes: try WireJSONCompatibility.data(result))))
    }
}

extension CustomCapabilityProbeStep: Equatable {}

func customCapabilityTemplate(wire: ProviderToolContract.Wire = .responses) -> HTTPClientRequest {
    var request = HTTPClientRequest(
        url: "https://provider.example/v1/\(wire == .responses ? "responses" : "chat/completions")")
    request.method = .POST
    request.headers = [
        "authorization": "Bearer synthetic-key", "x-api-key": "synthetic-api-key", "content-type": "application/json",
        "content-length": "2000", "x-client-session": "private-session", "cookie": "private-cookie",
        "x-codex-turn-metadata": "private-turn", "openai-organization": "synthetic-org",
    ]
    request.body = .bytes(ByteBuffer(string: "private-client-prompt-and-history"))
    return request
}
