import Foundation
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Provider streaming tool ownership")
struct ProviderToolContractStreamingTests {
    @Test("Anthropic validates content starts and prepopulated message content")
    func anthropicStarts() throws {
        let allowed: [String: Any] = ["type": "tool_use", "name": "read", "id": "call", "input": [:]]
        for block: [String: Any] in [
            allowed, ["type": "tool_use", "name": "unknown"], ["type": "server_tool_use", "name": "read"],
        ] {
            let payloads: [[String: Any]] = [
                ["type": "content_block_start", "index": 0, "content_block": block],
                ["type": "message_start", "message": ["content": [block]]],
            ]
            for payload in payloads {
                var contract = try anthropicContract()
                if block["id"] != nil {
                    try contract.validateFrame(frame(payload))
                } else {
                    let expected: ProviderToolContract.Error =
                        block["type"] as? String == "tool_use" ? .undeclaredTool(name: "unknown") : .providerOwnedTool
                    #expect(throws: expected) { try contract.validateFrame(frame(payload)) }
                }
            }
        }
    }

    @Test("Responses validates added, done, created, and terminal output before publication")
    func responsesItems() throws {
        for type in [
            "response.output_item.added", "response.output_item.done", "response.created", "response.completed",
        ] {
            for name in ["read", "unknown"] {
                var contract = try responsesContract()
                let item: [String: Any] = ["type": "function_call", "name": name, "id": "call", "arguments": "{}"]
                let payload: [String: Any] =
                    type.contains("output_item")
                    ? ["type": type, "output_index": 0, "item": item]
                    : ["type": type, "response": ["output": [item]]]
                if name == "read" {
                    try contract.validateFrame(frame(payload))
                } else {
                    #expect(throws: ProviderToolContract.Error.undeclaredTool(name: name)) {
                        try contract.validateFrame(frame(payload))
                    }
                }
            }
        }
    }

    @Test("Native Responses server tools fail in item and terminal frames")
    func responsesServerTools() throws {
        var contract = try responsesContract()
        let native = ["type": "web_search_call", "id": "search", "status": "completed"]
        #expect(throws: ProviderToolContract.Error.providerOwnedTool) {
            try contract.validateFrame(
                frame(["type": "response.output_item.added", "output_index": 0, "item": native]))
        }
        #expect(throws: ProviderToolContract.Error.providerOwnedTool) {
            try contract.validateFrame(
                frame(["type": "response.failed", "response": ["output": [native], "error": NSNull()]]))
        }
    }

    @Test("Function argument events require a declared item and cannot change its name")
    func responsesArguments() throws {
        var contract = try responsesContract()
        let delta: [String: Any] = [
            "type": "response.function_call_arguments.delta", "item_id": "call", "delta": "{", "output_index": 0,
        ]
        #expect(throws: ProviderToolContract.Error.invalidResponse) {
            try contract.validateFrame(frame(delta))
        }
        try contract.validateFrame(
            frame([
                "type": "response.output_item.added", "output_index": 0,
                "item": ["type": "function_call", "name": "read", "id": "call", "arguments": ""],
            ]))
        try contract.validateFrame(frame(delta))
        #expect(throws: ProviderToolContract.Error.undeclaredTool(name: "unknown")) {
            try contract.validateFrame(
                frame([
                    "type": "response.function_call_arguments.done", "item_id": "call", "output_index": 0,
                    "name": "unknown", "arguments": "{}",
                ]))
        }
    }

    @Test("Responses argument metadata nulls retain the declared name and namespace")
    func nullableResponsesMetadata() throws {
        for kind in ["function", "custom"] {
            var contract = try ProviderToolContract(
                wire: .responses,
                requestBody: jsonData([
                    "tools": [["type": "namespace", "name": "files", "tools": [["type": kind, "name": "read"]]]]
                ]))
            try contract.validateFrame(
                frame([
                    "type": "response.output_item.added", "output_index": 0,
                    "item": [
                        "type": kind == "function" ? "function_call" : "custom_tool_call",
                        "name": "read", "namespace": "files", "id": "call", "arguments": "", "input": "",
                    ],
                ]))
            let event = kind == "function" ? "response.function_call_arguments" : "response.custom_tool_call_input"
            for fields: [String: Any] in [
                [:], ["name": NSNull(), "namespace": NSNull(), "call_id": NSNull()],
                ["name": "read", "namespace": NSNull()], ["name": NSNull(), "namespace": "files"],
            ] {
                for phase in ["delta", "done"] {
                    var payload = fields
                    payload["type"] = "\(event).\(phase)"
                    payload["item_id"] = "call"
                    payload["delta"] = "{}"
                    payload["arguments"] = "{}"
                    payload["input"] = "{}"
                    try contract.validateFrame(frame(payload))
                }
            }
            try contract.finish()
        }
    }

    @Test("A Responses argument continuation cannot change namespace when its name is absent")
    func changedResponsesNamespace() throws {
        var contract = try ProviderToolContract(
            wire: .responses,
            requestBody: jsonData([
                "tools": ["files", "other"].map {
                    ["type": "namespace", "name": $0, "tools": [["type": "function", "name": "read"]]]
                }
            ]))
        try contract.validateFrame(
            frame([
                "type": "response.output_item.added",
                "item": ["type": "function_call", "name": "read", "namespace": "files", "id": "call"],
            ]))
        for fields: [String: Any] in [["namespace": "other"], ["name": NSNull(), "namespace": "other"]] {
            var payload = fields
            payload["type"] = "response.function_call_arguments.delta"
            payload["item_id"] = "call"
            #expect(throws: ProviderToolContract.Error.invalidResponse) { try contract.validateFrame(frame(payload)) }
        }
    }

    @Test("Chat function names and JSON arguments may both be fragmented")
    func fragmentedChatNames() throws {
        var contract = try chatContract()
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 4_096)
        let chunks = try [
            chatChunk(["index": 2, "type": "function", "function": ["name": "re", "arguments": ""]]),
            chatChunk(["index": 2, "function": ["arguments": "{\"path\":"]]),
            chatChunk(["index": 2, "function": ["name": "ad", "arguments": "\"file\"}"]]),
            frame(["choices": [["index": 0, "delta": [:], "finish_reason": "tool_calls"]]]),
        ]
        for chunk in chunks {
            let encoded = Data("data: ".utf8) + chunk.data + Data("\n\n".utf8)
            for byte in encoded {
                for decoded in try decoder.append(ByteBuffer(bytes: [byte])) {
                    try contract.validateFrame(decoded)
                }
            }
        }
        #expect(try decoder.finish().isEmpty)
        try contract.validateFrame(ServerSentEventFrame(event: nil, data: Data(), terminal: true))
        try contract.finish()
    }

    @Test("Impossible Chat names fail as soon as their prefix leaves the catalog")
    func unknownChatName() throws {
        var contract = try chatContract()
        try contract.validateFrame(chatChunk(["index": 0, "function": ["name": "re"]]))
        #expect(throws: ProviderToolContract.Error.undeclaredTool(name: "remove")) {
            try contract.validateFrame(chatChunk(["index": 0, "function": ["name": "move"]]))
        }
    }

    @Test("A complete declared Chat tool name may repeat on argument continuations")
    func repeatedCompleteChatName() throws {
        var contract = try chatContract()
        for name in ["re", "ad", "read", "read"] {
            try contract.validateFrame(chatChunk(["index": 0, "function": ["name": name, "arguments": " "]]))
        }
        try contract.finish()
        #expect(throws: ProviderToolContract.Error.undeclaredTool(name: "readwrite")) {
            try contract.validateFrame(chatChunk(["index": 0, "function": ["name": "write"]]))
        }
        var incomplete = try chatContract()
        try incomplete.validateFrame(chatChunk(["index": 0, "function": ["name": "re"]]))
        #expect(throws: ProviderToolContract.Error.undeclaredTool(name: "rere")) {
            try incomplete.validateFrame(chatChunk(["index": 0, "function": ["name": "re"]]))
        }
    }

    @Test("Chat argument continuations may explicitly null unchanged identity fields")
    func nullableChatContinuation() throws {
        for kind: Any in ["function", NSNull()] {
            var contract = try chatContract()
            try contract.validateFrame(
                chatChunk([
                    "index": 0, "id": "call_read", "type": "function",
                    "function": ["name": "read", "arguments": "{\"path\":"],
                ]))
            try contract.validateFrame(
                chatChunk([
                    "index": 0, "id": NSNull(), "type": kind,
                    "function": ["name": NSNull(), "arguments": "\"file\"}"],
                ]))
            try contract.validateFrame(frame(["choices": [["index": 0, "finish_reason": "tool_calls"]]]))
            try contract.validateFrame(frame(["choices": [], "usage": ["total_tokens": 1]]))
            try contract.finish()
        }
    }

    @Test("Null Chat identity fields do not authorize an unknown or unfinished call")
    func nullableChatIdentityStillNeedsDeclaration() throws {
        let unknown: [String: Any] = [
            "index": 0, "id": NSNull(), "type": NSNull(),
            "function": ["name": NSNull(), "arguments": "{}"],
        ]
        var empty = try ProviderToolContract(wire: .chatCompletions, requestBody: jsonData([:]))
        #expect(throws: ProviderToolContract.Error.undeclaredTool(name: "")) {
            try empty.validateFrame(chatChunk(unknown))
        }
        var declared = try chatContract()
        try declared.validateFrame(chatChunk(unknown))
        #expect(throws: ProviderToolContract.Error.invalidResponse) { try declared.finish() }
        #expect(throws: ProviderToolContract.Error.undeclaredTool(name: "unknown")) {
            try declared.validateFrame(chatChunk(["index": 0, "function": ["name": "unknown"]]))
        }
    }

    @Test("A possible prefix must become a complete declared name by every terminal")
    func incompleteChatName() throws {
        for terminal in 0..<3 {
            var contract = try chatContract()
            try contract.validateFrame(chatChunk(["index": 0, "function": ["name": "rea"]]))
            #expect(throws: ProviderToolContract.Error.undeclaredTool(name: "rea")) {
                switch terminal {
                case 0:
                    try contract.finish()
                case 1:
                    try contract.validateFrame(ServerSentEventFrame(event: nil, data: Data(), terminal: true))
                default:
                    try contract.validateFrame(
                        frame(["choices": [["index": 0, "delta": [:], "finish_reason": "tool_calls"]]]))
                }
            }
        }
    }

    @Test("Chat cannot introduce a tool when no current declaration exists")
    func undeclaredChatStart() throws {
        var contract = try ProviderToolContract(wire: .chatCompletions, requestBody: jsonData([:]))
        #expect(throws: ProviderToolContract.Error.undeclaredTool(name: "")) {
            try contract.validateFrame(chatChunk(["index": 0, "function": ["arguments": ""]]))
        }
    }

    @Test("Chat indices isolate names and reject new calls after a choice finishes")
    func interleavedChatCalls() throws {
        var contract = try chatContract()
        try contract.validateFrame(chatChunk(["index": 2, "function": ["name": "re"]], choice: 3))
        try contract.validateFrame(chatChunk(["index": 0, "function": ["name": "read"]]))
        try contract.validateFrame(chatChunk(["index": 2, "function": ["name": "ad"]], choice: 3))
        try contract.validateFrame(frame(["choices": [["index": 0, "finish_reason": "tool_calls"]]]))
        #expect(throws: ProviderToolContract.Error.invalidResponse) {
            try contract.validateFrame(chatChunk(["index": 1, "function": ["name": "read"]]))
        }
        try contract.finish()
    }

    @Test("Empty frames, errors, usage, and future non-tool events remain transparent")
    func streamingMetadata() throws {
        for wire in [ProviderToolContract.Wire.anthropic, .responses, .chatCompletions] {
            var contract = try ProviderToolContract(wire: wire, requestBody: jsonData([:]))
            try contract.validateFrame(ServerSentEventFrame(event: "ping", data: Data(), terminal: false))
            try contract.validateFrame(frame(["type": "error", "error": ["message": "private"]]))
            try contract.validateFrame(frame(["type": "future_metadata", "usage": ["count": 1]]))
            try contract.validateFrame(frame(["choices": [], "usage": ["total_tokens": 1]]))
            try contract.finish()
        }
    }

    private func anthropicContract() throws -> ProviderToolContract {
        try ProviderToolContract(wire: .anthropic, requestBody: jsonData(["tools": [["name": "read"]]]))
    }

    private func responsesContract() throws -> ProviderToolContract {
        try ProviderToolContract(
            wire: .responses, requestBody: jsonData(["tools": [["type": "function", "name": "read"]]]))
    }

    private func chatContract() throws -> ProviderToolContract {
        try ProviderToolContract(
            wire: .chatCompletions,
            requestBody: jsonData(["tools": [["type": "function", "function": ["name": "read"]]]])
        )
    }

    private func chatChunk(_ call: [String: Any], choice: Int = 0) throws -> ServerSentEventFrame {
        try frame(["choices": [["index": choice, "delta": ["tool_calls": [call]]]]])
    }

    private func frame(_ payload: [String: Any]) throws -> ServerSentEventFrame {
        ServerSentEventFrame(event: payload["type"] as? String, data: try jsonData(payload), terminal: false)
    }
}
