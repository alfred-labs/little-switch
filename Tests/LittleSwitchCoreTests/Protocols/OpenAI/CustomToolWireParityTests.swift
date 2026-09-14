import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Custom tool wire parity")
struct CustomToolWireParityTests {
    @Test("Chat custom declarations and forced choices preserve format and collision-safe identity")
    func chatCustomDeclaration() throws {
        let prepared = try chatPrepared()
        let upstream = try chatJSONObject(prepared.upstreamBody)
        let tools = try #require(upstream["tools"] as? [[String: Any]])
        let custom = try #require(tools.last?["custom"] as? [String: Any])
        let wireName = try namespaceName(prepared.toolBindings)
        #expect(tools.count == 2)
        #expect(tools.last?["type"] as? String == "custom")
        #expect(custom["name"] as? String == wireName)
        #expect(custom["format"] as? NSDictionary == customFormat as NSDictionary)
        #expect(
            upstream["tool_choice"] as? NSDictionary == ["type": "custom", "custom": ["name": wireName]] as NSDictionary
        )
    }

    @Test("Chat custom JSON restores namespace and preserves opaque input")
    func chatCustomOutput() throws {
        let prepared = try chatPrepared()
        let name = try namespaceName(prepared.toolBindings)
        let response = try OpenAIResponsesChatCompletions.project(
            responseBody: chatJSONData([
                "choices": [
                    [
                        "finish_reason": "tool_calls",
                        "message": [
                            "tool_calls": [
                                ["type": "custom", "id": "call_patch", "custom": ["name": name, "input": rawInput]]
                            ]
                        ],
                    ]
                ]
            ]),
            prepared: prepared)
        let output = try #require(chatJSONObject(response)["output"] as? [[String: Any]])
        try expectCustom(output)
    }

    @Test("Chat custom SSE publishes input deltas and the identical completed custom call")
    func chatCustomStream() throws {
        let prepared = try chatPrepared()
        let name = try namespaceName(prepared.toolBindings)
        let frames = try [
            chatChunkFrame(choices: [
                chatChoice(delta: [
                    "tool_calls": [
                        [
                            "index": 0, "id": "call_patch", "type": "custom",
                            "custom": ["name": name, "input": "*** Begin Patch\n"],
                        ]
                    ]
                ])
            ]),
            chatChunkFrame(choices: [
                chatChoice(delta: [
                    "tool_calls": [
                        [
                            "index": 0, "custom": ["input": "é🙂\n*** End Patch"],
                        ]
                    ]
                ])
            ]),
            chatChunkFrame(
                choices: [
                    chatChoice(
                        delta: [:],
                        finishReason: "tool_calls")
                ],
                usage: ["prompt_tokens": 0, "completion_tokens": 0]),
            chatDoneFrame(),
        ]
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
        var session = ResponsesPublicStreamSession(chatCompletions: prepared)
        var publicFrames: [Data] = []
        for frame in frames {
            for event in try accumulator.consume(frame) {
                if case .responseStarted(let data) = event {
                    publicFrames += try session.start(responseJSON: data)
                } else {
                    publicFrames += try session.consumePublic(event)
                }
            }
        }
        let turn = try accumulator.finish()
        publicFrames += try session.finish(
            responseJSON: turn.rootJSON,
            usage: .init(
                inputTokens: 0,
                outputTokens: 0))
        let output = try #require(chatJSONObject(turn.rootJSON)["output"] as? [[String: Any]])
        try expectCustom(output)
        let events = try publicEvents(publicFrames)
        let inputDeltas = events.filter { $0.name == "response.custom_tool_call_input.delta" }
        #expect(inputDeltas.compactMap { $0.payload["delta"] as? String }.joined() == rawInput)
        #expect(
            events.first { $0.name == "response.custom_tool_call_input.done" }?.payload["input"] as? String == rawInput)
        let completed = try #require(
            events.last { $0.name == "response.completed" }?.payload["response"] as? [String: Any])
        try expectCustom(try #require(completed["output"] as? [[String: Any]]))
    }

    @Test("Adapted native custom JSON restores the same namespace and opaque input")
    func nativeCustomOutput() throws {
        let prepared = try #require(
            try OpenAIResponsesWebSearch.prepare(
                body: request(),
                targetModel: "upstream",
                configuration: .firecrawlCloud))
        let name = try namespaceName(prepared.toolBindings)
        let item = customCall(name: name)
        let turn = try OpenAIResponsesWebSearch.parseModelTurn(
            responseData(
                responseObject(
                    id: "resp_custom",
                    createdAt: 1,
                    status: "completed",
                    output: [item],
                    usage: .init(
                        inputTokens: 1,
                        outputTokens: 1))))
        let projected = try OpenAIResponsesWebSearch.nonStreamingResponse(
            prepared: prepared,
            traces: [],
            finalTurn: turn,
            usage: .init(
                inputTokens: 1,
                outputTokens: 1))
        try expectCustom(try #require(chatJSONObject(projected)["output"] as? [[String: Any]]))
    }

    @Test("Adapted native custom SSE preserves its namespace through input events and completion")
    func nativeCustomStream() throws {
        let prepared = try #require(
            try OpenAIResponsesWebSearch.prepare(
                body: request(),
                targetModel: "upstream",
                configuration: .firecrawlCloud))
        let item = try customCall(name: namespaceName(prepared.toolBindings))
        var start = item
        start["input"] = ""
        start["status"] = "in_progress"
        let frames = try [
            createdFrame(
                id: "resp_custom",
                createdAt: 1),
            responsesFrame("response.output_item.added", ["output_index": 0, "item": start]),
            responsesFrame(
                "response.custom_tool_call_input.delta", ["output_index": 0, "item_id": "ct_custom", "delta": rawInput]),
            responsesFrame(
                "response.custom_tool_call_input.done", ["output_index": 0, "item_id": "ct_custom", "input": rawInput]),
            responsesFrame("response.output_item.done", ["output_index": 0, "item": item]),
            responsesFrame(
                "response.completed",
                [
                    "response": responseObject(
                        id: "resp_custom",
                        createdAt: 1,
                        status: "completed",
                        output: [item],
                        usage: .init(
                            inputTokens: 1,
                            outputTokens: 1))
                ]),
        ]
        var accumulator = OpenAIResponsesTurnAccumulator(
            maximumTurnBytes: 64 * 1_024,
            toolBindings: prepared.toolBindings,
            declaredToolBindings: prepared.declaredToolBindings,
            toolNameCatalog: prepared.toolNameCatalog)
        var session = ResponsesPublicStreamSession(webSearch: prepared)
        var publicFrames: [Data] = []
        for frame in frames {
            for event in try accumulator.consume(frame) {
                if case .responseStarted(let data) = event {
                    publicFrames += try session.start(responseJSON: data)
                } else {
                    publicFrames += try session.consumePublic(event)
                }
            }
        }
        let turn = try accumulator.finish()
        publicFrames += try session.finish(
            responseJSON: turn.rootJSON,
            usage: .init(
                inputTokens: 1,
                outputTokens: 1))
        let events = try publicEvents(publicFrames)
        #expect(
            events.first { $0.name == "response.custom_tool_call_input.delta" }?.payload["delta"] as? String == rawInput
        )
        #expect(
            events.first { $0.name == "response.custom_tool_call_input.done" }?.payload["input"] as? String == rawInput)
        let completed = try #require(
            events.last { $0.name == "response.completed" }?.payload["response"] as? [String: Any])
        try expectCustom(try #require(completed["output"] as? [[String: Any]]))
    }

    @Test("Buffered custom JSON becomes the same public SSE on both provider wires", arguments: [false, true])
    func customJSONToStream(_ chat: Bool) throws {
        var request = try chatJSONObject(request())
        request["stream"] = true
        let body = try chatJSONData(request)
        let stream: Data
        if chat {
            let prepared = try OpenAIResponsesChatCompletions.prepare(body: body, targetModel: "upstream")
            let name = try namespaceName(prepared.toolBindings)
            stream = try OpenAIResponsesChatCompletions.project(
                responseBody: chatJSONData([
                    "choices": [
                        [
                            "finish_reason": "tool_calls",
                            "message": [
                                "tool_calls": [
                                    [
                                        "type": "custom", "id": "call_patch",
                                        "custom": ["name": name, "input": rawInput],
                                    ]
                                ]
                            ],
                        ]
                    ]
                ]),
                prepared: prepared)
        } else {
            let prepared = try #require(
                try OpenAIResponsesWebSearch.prepare(
                    body: body,
                    targetModel: "upstream",
                    configuration: .firecrawlCloud))
            let item = try customCall(name: namespaceName(prepared.toolBindings))
            let usage = ResponsesUsage(inputTokens: 1, outputTokens: 1)
            let turn = try OpenAIResponsesWebSearch.parseModelTurn(
                responseData(
                    responseObject(
                        id: "resp_custom", createdAt: 1, status: "completed", output: [item], usage: usage)))
            stream = try OpenAIResponsesWebSearch.streamingResponse(
                prepared: prepared, traces: [], finalTurn: turn, usage: usage)
        }
        let events = try ResponsesStreamingTestSupport.events(stream)
        #expect(
            events.first { $0.name == "response.custom_tool_call_input.delta" }?.payload["delta"] as? String == rawInput
        )
        #expect(
            events.first { $0.name == "response.custom_tool_call_input.done" }?.payload["input"] as? String == rawInput)
        let added = try #require(
            events.first { $0.name == "response.output_item.added" }?.payload["item"] as? [String: Any])
        #expect(added["type"] as? String == "custom_tool_call")
        #expect(added["namespace"] as? String == "workspace")
        #expect(added["name"] as? String == "patch")
        #expect((added["input"] as? String)?.isEmpty == true)
        let completed = try #require(events.last?.payload["response"] as? [String: Any])
        try expectCustom(try #require(completed["output"] as? [[String: Any]]))
    }

    private var rawInput: String { "*** Begin Patch\né🙂\n*** End Patch" }

    private var customFormat: [String: Any] {
        ["type": "grammar", "syntax": "lark", "definition": "start: WORD\n%import common.WORD"]
    }

    private func request() throws -> Data {
        try chatJSONData([
            "model": "client", "input": "Apply the patch.",
            "tools": [
                ["type": "custom", "name": "workspace__patch"],
                [
                    "type": "namespace", "name": "workspace",
                    "tools": [["type": "custom", "name": "patch", "format": customFormat]],
                ],
            ],
            "tool_choice": ["type": "custom", "namespace": "workspace", "name": "patch"],
        ])
    }

    private func chatPrepared() throws -> PreparedResponsesChatCompletionsRequest {
        try OpenAIResponsesChatCompletions.prepare(
            body: request(),
            targetModel: "upstream",
            mode: .streaming(toolStream: true))
    }

    private func namespaceName(_ bindings: [String: ResponsesToolNamespaces.Binding]) throws -> String {
        let name = try #require(
            bindings.first {
                $0.value
                    == .init(
                        namespace: "workspace",
                        name: "patch")
            }?.key)
        #expect(name != "workspace__patch")
        return name
    }

    private func customCall(name: String) -> [String: Any] {
        [
            "id": "ct_custom", "type": "custom_tool_call", "status": "completed", "call_id": "call_patch", "name": name,
            "input": rawInput,
        ]
    }

    private func expectCustom(_ output: [[String: Any]]) throws {
        let item = try #require(output.first)
        #expect(output.count == 1)
        #expect(item["type"] as? String == "custom_tool_call")
        #expect(item["name"] as? String == "patch")
        #expect(item["namespace"] as? String == "workspace")
        #expect(item["call_id"] as? String == "call_patch")
        #expect(item["input"] as? String == rawInput)
        #expect(item["arguments"] == nil)
    }
}
