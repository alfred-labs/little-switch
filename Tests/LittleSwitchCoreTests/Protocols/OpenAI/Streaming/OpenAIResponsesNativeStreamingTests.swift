import Foundation
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI Responses native streaming restoration")
struct OpenAIResponsesNativeStreamingTests {
    private func flattenedCallFrames(emittedName: String) throws -> [ServerSentEventFrame] {
        let added = functionCallItem(
            id: "fc_spawn",
            callID: "call_spawn",
            name: emittedName,
            arguments: "",
            status: "in_progress"
        )
        let done = functionCallItem(
            id: "fc_spawn",
            callID: "call_spawn",
            name: emittedName,
            arguments: #"{"message":"Go"}"#,
            status: "completed"
        )
        let terminal = responseObject(
            id: "resp_native",
            createdAt: 10,
            status: "completed",
            output: [done],
            usage: ResponsesUsage(inputTokens: 4, outputTokens: 2)
        )
        return try [
            responsesFrame(
                "response.created",
                [
                    "response": responseObject(
                        id: "resp_native",
                        createdAt: 10,
                        status: "in_progress",
                        output: [],
                        usage: nil
                    )
                ]
            ),
            responsesFrame("response.output_item.added", ["output_index": 0, "item": added]),
            responsesFrame(
                "response.function_call_arguments.delta",
                [
                    "output_index": 0,
                    "item_id": "fc_spawn",
                    "call_id": "call_spawn",
                    "name": emittedName,
                    "delta": #"{"#,
                ]
            ),
            responsesFrame(
                "response.function_call_arguments.done",
                [
                    "output_index": 0,
                    "item_id": "fc_spawn",
                    "call_id": "call_spawn",
                    "name": emittedName,
                    "arguments": #"{"message":"Go"}"#,
                ]
            ),
            responsesFrame("response.output_item.done", ["output_index": 0, "item": done]),
            responsesFrame("response.completed", ["response": terminal]),
        ]
    }

    @Test("Chat sessions expose no native bindings")
    func chatSessionsExposeNoBindings() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: try responseData(["model": "route", "input": "Hello."]),
            targetModel: "upstream"
        )
        let session = ResponsesPublicStreamSession(chatCompletions: prepared)
        #expect(session.nativeToolBindings.isEmpty)
        #expect(session.nativeDeclaredToolBindings.isEmpty)
        #expect(session.nativeToolNameCatalog == ProviderToolNameCatalog())
    }

    @Test("A flattened provider call streams back under the restored pair")
    func restoresStreamedCall() throws {
        let bindings = [
            "collaboration__spawn_agent": ResponsesToolNamespaces.Binding(
                namespace: "collaboration",
                name: "spawn_agent"
            )
        ]
        let prepared = PreparedResponsesWebSearchRequest(
            upstreamBody: Data(),
            originalBody: try responseData(["model": "little-switch-route"]),
            originalModel: "little-switch-route",
            originalToolsJSON: Data("[]".utf8),
            originalInputJSON: Data("[]".utf8),
            streaming: true,
            maximumUses: 3,
            toolBindings: bindings
        )

        var accumulator = OpenAIResponsesTurnAccumulator(
            maximumTurnBytes: 64 * 1_024,
            toolBindings: bindings
        )
        var events: [ResponsesProviderStreamEvent] = []
        for frame in try flattenedCallFrames(emittedName: "collaboration__spawn_agent") {
            events += try accumulator.consume(frame)
        }
        _ = try accumulator.finish()

        var session = ResponsesPublicStreamSession(webSearch: prepared)
        var wire = Data()
        for event in events {
            if session.started {
                wire += try session.consumePublic(event).joined()
                continue
            }
            guard case .responseStarted(let responseJSON) = event else {
                Issue.record("The first native event must start the session")
                return
            }
            wire += try session.start(responseJSON: responseJSON).joined()
        }

        let text = try #require(String(bytes: wire, encoding: .utf8))
        #expect(text.contains("response.output_item.added"))
        #expect(text.contains("response.function_call_arguments.delta"))
        #expect(text.contains(#""name":"spawn_agent""#))
        #expect(text.contains(#""namespace":"collaboration""#))
        #expect(!text.contains("collaboration__spawn_agent"))
    }

    @Test("A near-miss streamed call resolves through the declared bindings")
    func restoresNearMissStreamedCall() throws {
        let bindings = [
            "collaboration__spawn_agent": ResponsesToolNamespaces.Binding(
                namespace: "collaboration",
                name: "spawn_agent"
            )
        ]
        let prepared = PreparedResponsesWebSearchRequest(
            upstreamBody: Data(),
            originalBody: try responseData(["model": "little-switch-route"]),
            originalModel: "little-switch-route",
            originalToolsJSON: try responseData([
                [
                    "type": "namespace",
                    "name": "collaboration",
                    "tools": [
                        [
                            "type": "function",
                            "name": "spawn_agent",
                            "parameters": ["type": "object", "properties": [:]],
                        ]
                    ],
                ]
            ]),
            originalInputJSON: Data("[]".utf8),
            streaming: true,
            maximumUses: 3,
            toolBindings: bindings
        )

        // The production failure shape: the backend emits the bare child name
        // instead of the flattened wire name.
        let frames = try flattenedCallFrames(emittedName: "spawn_agent")

        var accumulator = OpenAIResponsesTurnAccumulator(
            maximumTurnBytes: 64 * 1_024,
            toolBindings: bindings,
            declaredToolBindings: bindings
        )
        var events: [ResponsesProviderStreamEvent] = []
        for frame in frames {
            events += try accumulator.consume(frame)
        }
        _ = try accumulator.finish()

        var session = ResponsesPublicStreamSession(webSearch: prepared)
        var wire = Data()
        for event in events {
            if session.started {
                wire += try session.consumePublic(event).joined()
                continue
            }
            guard case .responseStarted(let responseJSON) = event else {
                Issue.record("The first native event must start the session")
                return
            }
            wire += try session.start(responseJSON: responseJSON).joined()
        }

        let text = try #require(String(bytes: wire, encoding: .utf8))
        #expect(text.contains(#""name":"spawn_agent""#))
        #expect(text.contains(#""namespace":"collaboration""#))
        #expect(!text.contains("collaboration__spawn_agent"))
    }

    @Test("Unbound calls keep their plain name beside bindings")
    func unboundCallsPassThrough() throws {
        let bindings = [
            "collaboration__spawn_agent": ResponsesToolNamespaces.Binding(
                namespace: "collaboration",
                name: "spawn_agent"
            )
        ]
        let added = functionCallItem(
            id: "fc_read",
            callID: "call_read",
            name: "read_file",
            arguments: "",
            status: "in_progress"
        )
        let done = functionCallItem(
            id: "fc_read",
            callID: "call_read",
            name: "read_file",
            arguments: #"{"path":"README.md"}"#,
            status: "completed"
        )
        let terminal = responseObject(
            id: "resp_plain",
            createdAt: 10,
            status: "completed",
            output: [done],
            usage: ResponsesUsage(inputTokens: 4, outputTokens: 2)
        )
        let frames = try [
            responsesFrame(
                "response.created",
                [
                    "response": responseObject(
                        id: "resp_plain",
                        createdAt: 10,
                        status: "in_progress",
                        output: [],
                        usage: nil
                    )
                ]
            ),
            responsesFrame("response.output_item.added", ["output_index": 0, "item": added]),
            responsesFrame(
                "response.function_call_arguments.done",
                [
                    "output_index": 0,
                    "item_id": "fc_read",
                    "call_id": "call_read",
                    "name": "read_file",
                    "arguments": #"{"path":"README.md"}"#,
                ]
            ),
            responsesFrame("response.output_item.done", ["output_index": 0, "item": done]),
            responsesFrame("response.completed", ["response": terminal]),
        ]

        var accumulator = OpenAIResponsesTurnAccumulator(
            maximumTurnBytes: 64 * 1_024,
            toolBindings: bindings
        )
        var events: [ResponsesProviderStreamEvent] = []
        for frame in frames {
            events += try accumulator.consume(frame)
        }
        _ = try accumulator.finish()

        let doneNames = events.compactMap { event -> String? in
            guard case .functionArgumentsDone(_, _, _, let name, _) = event else {
                return nil
            }
            return name
        }
        #expect(doneNames == ["read_file"])
    }
}
