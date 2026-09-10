import Foundation
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

@Suite("Provider tool contract namespace resolution")
struct ProviderToolContractNamespaceTests {
    /// The exact upstream body the search bridge produces for Codex's
    /// collaboration tools: flattened declarations plus the private search
    /// helper the model must not be able to hijack.
    private func requestBody() throws -> Data {
        try jsonData([
            "tools": [
                [
                    "type": "function",
                    "name": "collaboration__spawn_agent",
                    "description": "Spawn an agent.",
                    "parameters": ["type": "object", "properties": [:]],
                ],
                [
                    "type": "function",
                    "name": "collaboration__list_agents",
                    "description": "List agents.",
                    "parameters": ["type": "object", "properties": [:]],
                ],
                ["type": "function", "name": "web_search"],
            ]
        ])
    }

    private func bindings() -> [String: ResponsesToolNamespaces.Binding] {
        [
            "collaboration__spawn_agent": .init(namespace: "collaboration", name: "spawn_agent"),
            "collaboration__list_agents": .init(namespace: "collaboration", name: "list_agents"),
        ]
    }

    @Test("The four production near-miss variants validate against the declared children")
    func productionVariants() throws {
        for name in [
            "spawn_agent",
            "list_agents",
            "functions.collaboration.spawn_agent",
            "mcp__tools__collaboration_spawn_agent",
        ] {
            let contract = try ProviderToolContract(
                wire: .responses,
                requestBody: requestBody(),
                declaredToolBindings: bindings()
            )
            try contract.validateBuffered(
                jsonData(["output": [["type": "function_call", "id": "call_1", "name": name, "arguments": "{}"]]])
            )
        }
    }

    @Test("Without declared bindings the same near-miss still fails closed")
    func nearMissWithoutBindingsFailsClosed() throws {
        let contract = try ProviderToolContract(wire: .responses, requestBody: requestBody())
        #expect(throws: ProviderToolContract.Error.undeclaredTool) {
            try contract.validateBuffered(
                jsonData([
                    "output": [["type": "function_call", "id": "call_1", "name": "spawn_agent", "arguments": "{}"]]
                ])
            )
        }
    }

    @Test("A name no declaration can explain still fails closed")
    func unknownNameFailsClosed() throws {
        let contract = try ProviderToolContract(
            wire: .responses,
            requestBody: requestBody(),
            declaredToolBindings: bindings()
        )
        #expect(throws: ProviderToolContract.Error.undeclaredTool) {
            try contract.validateBuffered(
                jsonData([
                    "output": [
                        ["type": "function_call", "id": "call_1", "name": "totally_unknown", "arguments": "{}"]
                    ]
                ])
            )
        }
    }

    @Test("The private search tool is only reachable by its exact name")
    func privateToolNotHijackable() throws {
        // Declared bindings containing a collab child named like the private
        // tool must not make the bare private name resolve elsewhere.
        var bindings = self.bindings()
        bindings["collaboration__web_search"] = .init(namespace: "collaboration", name: "web_search")
        let contract = try ProviderToolContract(
            wire: .responses,
            requestBody: jsonData([
                "tools": [
                    ["type": "function", "name": "web_search"],
                    [
                        "type": "function",
                        "name": "collaboration__web_search",
                        "parameters": ["type": "object", "properties": [:]],
                    ],
                ]
            ]),
            declaredToolBindings: bindings
        )
        try contract.validateBuffered(
            jsonData(["output": [["type": "function_call", "id": "call_1", "name": "web_search", "arguments": "{}"]]])
        )
        // The bare name under a resolution attempt cannot masquerade as the
        // namespace child, and the namespace child cannot masquerade as the
        // private tool: each exact identity is distinct and both validate.
        try contract.validateBuffered(
            jsonData([
                "output": [
                    ["type": "function_call", "id": "call_2", "name": "collaboration__web_search", "arguments": "{}"]
                ]
            ])
        )
    }

    @Test("A restored pair validates when the namespace matches the declaration")
    func restoredPair() throws {
        let contract = try ProviderToolContract(
            wire: .responses,
            requestBody: requestBody(),
            declaredToolBindings: bindings()
        )
        try contract.validateBuffered(
            jsonData([
                "output": [
                    [
                        "type": "function_call",
                        "id": "call_1",
                        "name": "spawn_agent",
                        "namespace": "collaboration",
                        "arguments": "{}",
                    ]
                ]
            ])
        )
    }

    @Test("A restored pair with an undeclared namespace fails closed")
    func restoredPairWrongNamespace() throws {
        let contract = try ProviderToolContract(
            wire: .responses,
            requestBody: requestBody(),
            declaredToolBindings: bindings()
        )
        #expect(throws: ProviderToolContract.Error.undeclaredTool) {
            try contract.validateBuffered(
                jsonData([
                    "output": [
                        [
                            "type": "function_call",
                            "id": "call_1",
                            "name": "spawn_agent",
                            "namespace": "other",
                            "arguments": "{}",
                        ]
                    ]
                ])
            )
        }
    }

    @Test("Streaming frames resolve near-misses and keep the delta identity consistent")
    func streamingFrames() throws {
        var contract = try ProviderToolContract(
            wire: .responses,
            requestBody: requestBody(),
            declaredToolBindings: bindings()
        )
        let frames: [Data] = [
            try jsonData([
                "type": "response.created",
                "response": ["id": "resp_1", "object": "response", "status": "in_progress", "output": []],
            ]),
            try jsonData([
                "type": "response.output_item.added",
                "output_index": 0,
                "item": [
                    "id": "item_1",
                    "type": "function_call",
                    "call_id": "call_1",
                    "name": "spawn_agent",
                    "arguments": "",
                ],
            ]),
            try jsonData([
                "type": "response.function_call_arguments.delta",
                "item_id": "item_1",
                "delta": "{\"",
            ]),
            try jsonData([
                "type": "response.function_call_arguments.done",
                "item_id": "item_1",
                "name": "spawn_agent",
                "arguments": "{}",
            ]),
            try jsonData([
                "type": "response.completed",
                "response": [
                    "id": "resp_1",
                    "object": "response",
                    "status": "completed",
                    "output": [
                        [
                            "type": "function_call", "id": "item_1", "call_id": "call_1", "name": "spawn_agent",
                            "arguments": "{}",
                        ]
                    ],
                    "usage": ["input_tokens": 1, "output_tokens": 1],
                ],
            ]),
        ]
        for frame in frames {
            try contract.validateFrame(ServerSentEventFrame(event: nil, data: frame, terminal: false))
        }
        try contract.finish()
    }

    @Test("Chat streaming resolves a near-miss only when bindings are declared")
    func chatStreamingNearMiss() throws {
        let toolCall: [String: Any] = [
            "index": 0,
            "id": "call_1",
            "type": "function",
            "function": ["name": "spawn_agent", "arguments": "{}"],
        ]
        var withResolver = try ProviderToolContract(
            wire: .chatCompletions,
            requestBody: jsonData([
                "tools": [
                    [
                        "type": "function",
                        "function": [
                            "name": "collaboration__spawn_agent",
                            "parameters": ["type": "object", "properties": [:]],
                        ],
                    ]
                ]
            ]),
            declaredToolBindings: bindings()
        )
        try withResolver.validateFrame(
            ServerSentEventFrame(
                event: nil,
                data: jsonData(["choices": [["index": 0, "delta": ["tool_calls": [toolCall]]]]]),
                terminal: false
            ))
        try withResolver.validateFrame(
            ServerSentEventFrame(
                event: nil,
                data: jsonData(["choices": [["index": 0, "delta": [:], "finish_reason": "tool_calls"]]]),
                terminal: false
            ))
        try withResolver.finish()

        var strict = try ProviderToolContract(
            wire: .chatCompletions,
            requestBody: jsonData([
                "tools": [
                    [
                        "type": "function",
                        "function": [
                            "name": "collaboration__spawn_agent",
                            "parameters": ["type": "object", "properties": [:]],
                        ],
                    ]
                ]
            ])
        )
        #expect(throws: ProviderToolContract.Error.undeclaredTool) {
            try strict.validateFrame(
                ServerSentEventFrame(
                    event: nil,
                    data: jsonData(["choices": [["index": 0, "delta": ["tool_calls": [toolCall]]]]]),
                    terminal: false
                ))
        }
    }
}
