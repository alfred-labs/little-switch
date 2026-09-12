import AsyncHTTPClient
import Foundation
import HTTPTypes
import HummingbirdTesting
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("Compaction uses Chat Completions directly or after one capability fallback", arguments: [false, true])
    func compactionChatWire(fallback: Bool) async throws {
        let fixture = try makeFixture()
        if !fallback {
            await fixture.state.responsesCapabilities.record(
                providerID: fixture.snapshot.providers[0].id, supportsNative: false)
        }
        let summary = try responsesStreamObject(Data(compactionSummaryResponse().utf8))
        let calls = try #require(summary["output"] as? [[String: Any]])
        let chat = responsesModelResponse(id: "summary", output: calls)
        var responses: [HTTPClientResponse] = []
        if fallback { responses.append(response(status: .notFound, body: "missing")) }
        responses.append(response(status: .ok, body: chat))
        let transport = RecordingGatewayTransport(responses: responses)
        try await makeApplication(fixture: fixture, transport: transport).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: compactionRequest(model: "z.ai/glm-5.2"))
            )
            #expect(result.status == .ok)
            #expect(String(buffer: result.body).contains("little_switch_compaction"))
        }
        let requests = await transport.requests
        #expect(requests.count == (fallback ? 2 : 1))
        #expect(requests.last?.url.hasSuffix("/chat/completions") == true)
    }

    @Test("Native compaction consumes a fragmented Responses stream", arguments: [false, true])
    func compactionNativeStream(deferredSeparator: Bool) async throws {
        let fixture = try makeFixture()
        let summary = try responsesStreamObject(Data(compactionSummaryResponse().utf8))
        let item = try #require((summary["output"] as? [[String: Any]])?.first)
        let bytes = try ResponsesCompactionStream.encode(
            ResponsesCompactionResult(
                itemJSON: responsesStreamData(item), usage: ResponsesUsage(inputTokens: 20, outputTokens: 5)),
            model: "gpt-native",
            id: "resp_summary",
            createdAt: 1
        )
        var stream = try #require(String(bytes: bytes, encoding: .utf8))
        let argumentsDone = try responsesStreamData([
            "type": "response.function_call_arguments.done", "output_index": 0,
            "item_id": try #require(item["id"] as? String),
            "arguments": try #require(item["arguments"] as? String),
        ])
        let argumentsText = try #require(String(bytes: argumentsDone, encoding: .utf8))
        let completion = "event: response.function_call_arguments.done\ndata: \(argumentsText)\n\n"
        stream = stream.replacingOccurrences(
            of: "event: response.output_item.done\n", with: completion + "event: response.output_item.done\n")
        if deferredSeparator {
            stream.removeLast(2)
            stream += "\r\r"
        }
        let transport = RecordingGatewayTransport(responses: [
            streamingResponse(
                status: .ok, headers: ["content-type": "text/event-stream"], chunks: stream.map(String.init))
        ])
        try await makeApplication(fixture: fixture, transport: transport).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(bytes: compactionRequest(model: "gpt-native"))
            )
            #expect(result.status == .ok)
            var decoder = ServerSentEventDecoder(maximumFrameBytes: 32_768)
            let frames = try decoder.append(result.body) + decoder.finish()
            let terminal = try #require(frames.last)
            let root = try #require(responsesStreamObject(terminal.data)["response"] as? [String: Any])
            #expect((root["usage"] as? [String: Any])?["total_tokens"] as? Int == 25)
            #expect(
                frames.map(\.event) == [
                    "response.created", "response.in_progress", "response.output_item.added",
                    "response.output_item.done", "response.completed",
                ])
        }
    }

    @Test("Invalid compaction selections get one bounded repair carrying the reason", arguments: [false, true])
    func compactionRepair(failsAgain: Bool) async throws {
        let fixture = try makeFixture()
        let invalid = compactionSummaryResponse().replacingOccurrences(
            of: "Continue the implementation; the file was read.", with: ""
        )
        let transport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: invalid),
            response(status: .ok, body: failsAgain ? invalid : compactionSummaryResponse()),
        ])
        try await makeApplication(fixture: fixture, transport: transport).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: compactionRequest(model: "z.ai/glm-5.2"))
            )
            #expect(result.status == (failsAgain ? .badGateway : .ok))
            if !failsAgain { #expect(String(buffer: result.body).contains("\"total_tokens\":50")) }
        }
        let requests = await transport.requests
        #expect(requests.count == 2)
        let retried = try responsesStreamObject(try #require(requests.last).body)
        let repair = ((retried["input"] as? [[String: Any]])?.last?["content"] as? String) ?? ""
        #expect(repair.contains("Your previous create_summary call was invalid:"))
        #expect(repair.contains("summary"))
    }

    @Test("A context overflow trims the oldest removable transcript and retries once")
    func compactionOverflowTrim() async throws {
        let fixture = try makeFixture()
        var history: [[String: Any]] = []
        for index in 0..<24 {
            history.append([
                "type": "message", "role": "assistant",
                "content": [
                    ["type": "output_text", "text": "Step \(index): " + String(repeating: "detail ", count: 40)]
                ],
            ])
        }
        history.append(["type": "message", "role": "user", "content": "Finish the work."])
        var body = try responsesStreamObject(compactionRequest(model: "z.ai/glm-5.2"))
        body["input"] = history + [["type": "compaction_trigger"]]
        let requestBody = try responsesStreamData(body)
        let overflow = response(
            status: .badRequest,
            body:
                #"{"error":{"code":"context_length_exceeded","message":"The prompt is too long: 90000, model maximum context length: 80000"}}"#
        )
        let transport = RecordingGatewayTransport(responses: [
            overflow, response(status: .ok, body: compactionSummaryResponse()),
        ])
        try await makeApplication(fixture: fixture, transport: transport).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: requestBody)
            )
            #expect(result.status == .ok)
            #expect(String(buffer: result.body).contains("Compaction warning:"))
        }
        let requests = await transport.requests
        #expect(requests.count == 2)
        let first = try responsesStreamObject(try #require(requests.first).body)
        let trimmed = try responsesStreamObject(try #require(requests.last).body)
        let firstText = try ResponsesCompactionJSON.text(try #require(first["input"] as? [[String: Any]]))
        let trimmedText = try ResponsesCompactionJSON.text(try #require(trimmed["input"] as? [[String: Any]]))
        #expect(firstText.contains("Step 0:"))
        #expect(!trimmedText.contains("Step 0:"))
        #expect(trimmedText.contains("Step 23:"))
        #expect(trimmedText.contains("Finish the work."))
        #expect(
            (trimmed["instructions"] as? String ?? "").contains("Compaction warning:"))
    }

    @Test("A context overflow without removable history relays the failure")
    func compactionOverflowWithoutRemovableItems() async throws {
        let fixture = try makeFixture()
        let overflow = response(
            status: .payloadTooLarge,
            body: #"{"error":{"message":"The prompt is too long: 90000, model maximum context length: 80000"}}"#
        )
        let transport = RecordingGatewayTransport(responses: [overflow])
        try await makeApplication(fixture: fixture, transport: transport).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: compactionRequest(model: "z.ai/glm-5.2"))
            )
            #expect(result.status == .contentTooLarge)
            #expect(
                String(buffer: result.body).contains("context_length_exceeded")
                    || String(buffer: result.body).contains("too long"))
        }
        #expect(await transport.requests.count == 1)
    }

    @Test("An ordinary bad request never triggers the overflow trim")
    func compactionUnrelatedBadRequest() async throws {
        let fixture = try makeFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(status: .badRequest, body: #"{"error":{"message":"unrelated"}}"#),
            response(status: .badRequest, body: "not even json"),
        ])
        for _ in 0..<2 {
            let application = GatewayTests().makeApplication(fixture: fixture, transport: transport)
            try await application.test(.router) { client in
                let result = try await client.execute(
                    uri: "/v1/responses",
                    method: .post,
                    body: ByteBuffer(bytes: compactionRequest(model: "z.ai/glm-5.2"))
                )
                #expect(result.status == .badRequest)
            }
        }
        #expect(await transport.requests.count == 2)
    }

    @Test("A failed compaction preserves upstream errors and rejects malformed responses", arguments: [false, true])
    func compactionUpstreamFailure(malformed: Bool) async throws {
        let fixture = try makeFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(status: malformed ? .ok : .tooManyRequests, body: malformed ? "not-json" : "rate limited")
        ])
        try await makeApplication(fixture: fixture, transport: transport).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: compactionRequest(model: "z.ai/glm-5.2"))
            )
            #expect(result.status == (malformed ? .badGateway : .tooManyRequests))
            if !malformed { #expect(String(buffer: result.body) == "rate limited") }
        }
    }

    @Test("Invalid controls with opaque state fail before any recovery request")
    func invalidCompactionBeforeRecovery() async throws {
        let fixture = try makeFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let body =
            #"{"model":"z.ai/glm-5.2","stream":false,"input":[{"type":"compaction","encrypted_content":"opaque"},{"type":"compaction_trigger"}]}"#
        try await makeApplication(fixture: fixture, transport: transport).test(.router) { client in
            let result = try await client.execute(uri: "/v1/responses", method: .post, body: ByteBuffer(string: body))
            #expect(result.status == .badRequest)
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("Compaction retains the upstream failure status when its error body exceeds the limit")
    func compactionOversizedErrorBody() async throws {
        let fixture = try makeFixture()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: [
                response(status: .tooManyRequests, body: "long error body")
            ]),
            secretStore: fixture.secrets,
            maximumErrorBytes: 8,
            requiredAuthorityPort: nil
        )
        let plan = try #require(try ResponsesCompactionPlan.prepare(body: compactionRequest(model: "gpt-native")))
        let result = try await responder.responsesCompactionResponse(
            plan: plan, target: .native, incomingHeaders: [:], eventID: UUID()
        )
        #expect(result.status == .tooManyRequests)
    }
}
