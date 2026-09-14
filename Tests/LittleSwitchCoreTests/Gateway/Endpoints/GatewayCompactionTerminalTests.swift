import AsyncHTTPClient
import Foundation
import HTTPTypes
import HummingbirdTesting
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test(
        "A failed or incomplete summary cannot start a selection repair",
        arguments: CompactionTerminalScenario.cases
    )
    func compactionTerminalCannotRepair(scenario: CompactionTerminalScenario) async throws {
        let fixture = try makeFixture()
        if scenario.chat {
            await fixture.state.responsesCapabilities.record(
                providerID: fixture.snapshot.providers[0].id, supportsNative: false)
        }
        let successfulSummary = try scenario.successfulSummary()
        let transport = RecordingGatewayTransport(responses: [
            try scenario.response(), response(status: .ok, body: successfulSummary),
        ])
        try await makeApplication(fixture: fixture, transport: transport).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(bytes: compactionRequest(model: "z.ai/glm-5.2")))
            #expect(result.status == .badGateway)
            #expect(!String(buffer: result.body).contains("little_switch_compaction"))
        }
        #expect(await transport.requests.count == 1)
    }
}

struct CompactionTerminalScenario: Sendable, CustomTestStringConvertible {
    let chat: Bool
    let streaming: Bool
    let status: String

    static let cases: [Self] = ["failed", "incomplete"].flatMap { status in
        [false, true].flatMap { chat in
            [false, true].map { Self(chat: chat, streaming: $0, status: status) }
        }
    }

    var testDescription: String { "\(chat ? "Chat" : "Responses") \(streaming ? "SSE" : "JSON") \(status)" }

    func response() throws -> HTTPClientResponse {
        let body: Data
        if streaming {
            if chat {
                let frames = try [
                    chatChunkFrame(choices: [chatChoice(delta: ["role": "assistant", "content": ""])]),
                    chatChunkFrame(
                        choices: [chatChoice(delta: [:], finishReason: finishReason)],
                        usage: ["prompt_tokens": 3, "completion_tokens": 1, "total_tokens": 4]),
                    chatDoneFrame(),
                ]
                body = chatSSEChunks(frames).reduce(Data(), +)
            } else {
                body = try responsesGatewaySSE([
                    createdFrame(id: "resp_terminal", createdAt: 1),
                    responsesFrame("response.\(status)", ["response": terminalResponse]),
                ])
            }
        } else {
            body = try responsesStreamData(chat ? chatResponse : terminalResponse)
        }
        return HTTPClientResponse(
            status: .ok,
            headers: ["content-type": streaming ? "text/event-stream" : "application/json"],
            body: .bytes(ByteBuffer(bytes: body)))
    }

    func successfulSummary() throws -> String {
        guard chat else { return compactionSummaryResponse() }
        let summary = try responsesStreamObject(Data(compactionSummaryResponse().utf8))
        return responsesModelResponse(id: "summary", output: try #require(summary["output"] as? [[String: Any]]))
    }

    private var finishReason: String { status == "failed" ? "network_error" : "length" }

    private var terminalResponse: [String: Any] {
        [
            "id": "resp_terminal", "object": "response", "created_at": 1, "model": "glm-5.2",
            "status": status, "output": [],
            "error": status == "failed" ? ["code": "server_error", "message": "Provider unavailable"] : NSNull(),
            "incomplete_details": status == "incomplete" ? ["reason": "max_output_tokens"] : NSNull(),
            "usage": ["input_tokens": 3, "output_tokens": 1, "total_tokens": 4],
        ]
    }

    private var chatResponse: [String: Any] {
        [
            "id": "chatcmpl_terminal", "object": "chat.completion", "created": 1, "model": "glm-5.2",
            "choices": [
                [
                    "index": 0, "message": ["role": "assistant", "content": ""], "finish_reason": finishReason,
                ]
            ],
            "usage": ["prompt_tokens": 3, "completion_tokens": 1, "total_tokens": 4],
        ]
    }
}
