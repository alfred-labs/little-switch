import Foundation
import LittleSwitchCommon
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

@Suite("Provider tool allowed selections")
struct ProviderToolAllowedSelectionTests {
    @Test("A rejected namespace alias reports the observed identity", arguments: [false, true])
    func rejectedAliasDiagnostic(streaming: Bool) throws {
        for wire in [ProviderToolContract.Wire.responses, .chatCompletions] {
            let tool: [String: Any] =
                wire == .responses
                ? ["type": "function", "name": "workspace__run"]
                : ["type": "function", "function": ["name": "workspace__run"]]
            let selection: [String: Any] = ["mode": "auto", "tools": []]
            let choice: [String: Any] =
                wire == .responses
                ? ["type": "allowed_tools", "mode": "auto", "tools": []]
                : ["type": "allowed_tools", "allowed_tools": selection]
            var contract = try ProviderToolContract(
                wire: wire,
                requestBody: chatJSONData(["tools": [tool], "tool_choice": choice]),
                declaredToolBindings: ["workspace__run": .init(namespace: "workspace", name: "run")]
            )
            #expect(throws: ProviderToolContract.Error.undeclaredTool(name: "run", namespace: "workspace")) {
                try validate(
                    name: "run",
                    namespace: "workspace",
                    kind: "function",
                    wire: wire,
                    streaming: streaming,
                    contract: &contract
                )
            }
        }
    }

    @Test(
        "Only the allowed function or custom identity may be emitted", arguments: ["function", "custom"], [false, true])
    func restrictedOutputs(kind: String, streaming: Bool) throws {
        for wire in [ProviderToolContract.Wire.responses, .chatCompletions] {
            let body = try request(wire: wire, kind: kind, names: ["selected"])
            let catalog = try ProviderToolContractCatalog(wire: wire, requestBody: body)
            #expect(catalog.nameCatalog.declared == ["selected", "excluded"])
            var contract = try ProviderToolContract(wire: wire, requestBody: body)
            try validate(name: "selected", kind: kind, wire: wire, streaming: streaming, contract: &contract)
            var excluded = try ProviderToolContract(wire: wire, requestBody: body)
            #expect(throws: ProviderToolContract.Error.undeclaredTool(name: "excluded")) {
                try validate(name: "excluded", kind: kind, wire: wire, streaming: streaming, contract: &excluded)
            }
        }
    }

    @Test("Same-leaf namespaces keep distinct permissions", arguments: ["function", "custom"], [false, true])
    func namespaceSubset(kind: String, streaming: Bool) throws {
        let body = try chatJSONData([
            "tools": [
                ["type": kind, "name": "run"],
                ["type": "namespace", "name": "selected", "tools": [["type": kind, "name": "run"]]],
                ["type": "namespace", "name": "excluded", "tools": [["type": kind, "name": "run"]]],
            ],
            "tool_choice": [
                "type": "allowed_tools", "mode": "required",
                "tools": [["type": kind, "namespace": "selected", "name": "run"]],
            ],
        ])
        var selected = try ProviderToolContract(wire: .responses, requestBody: body)
        try validate(
            name: "run", namespace: "selected", kind: kind, wire: .responses, streaming: streaming, contract: &selected)
        for namespace: String? in [nil, "excluded"] {
            var excluded = try ProviderToolContract(wire: .responses, requestBody: body)
            #expect(throws: ProviderToolContract.Error.undeclaredTool(name: "run", namespace: namespace)) {
                try validate(
                    name: "run",
                    namespace: namespace,
                    kind: kind,
                    wire: .responses,
                    streaming: streaming,
                    contract: &excluded)
            }
        }
    }

    @Test("An excluded exact name cannot become a permitted namespace alias")
    func excludedExactName() throws {
        let body = try chatJSONData([
            "tools": [["type": "function", "name": "run"], ["type": "function", "name": "workspace__run"]],
            "tool_choice": [
                "type": "allowed_tools", "mode": "auto", "tools": [["type": "function", "name": "workspace__run"]],
            ],
        ])
        let bindings: [String: ResponsesToolNamespaces.Binding] = [
            "workspace__run": .init(namespace: "workspace", name: "run")
        ]
        var allowed = try ProviderToolContract(wire: .responses, requestBody: body, declaredToolBindings: bindings)
        try validate(name: "workspace__run", kind: "function", wire: .responses, streaming: false, contract: &allowed)
        for streaming in [false, true] {
            var excluded = try ProviderToolContract(wire: .responses, requestBody: body, declaredToolBindings: bindings)
            #expect(throws: ProviderToolContract.Error.undeclaredTool(name: "run")) {
                try validate(name: "run", kind: "function", wire: .responses, streaming: streaming, contract: &excluded)
            }
        }
    }

    @Test("The automatic empty subset permits text but no tool call")
    func emptySubset() throws {
        for wire in [ProviderToolContract.Wire.responses, .chatCompletions] {
            let body = try request(wire: wire, kind: "function", names: [])
            let contract = try ProviderToolContract(wire: wire, requestBody: body)
            try contract.validateBuffered(chatJSONData(wire == .responses ? ["output": []] : ["choices": []]))
            for streaming in [false, true] {
                var excluded = try ProviderToolContract(wire: wire, requestBody: body)
                #expect(throws: ProviderToolContract.Error.undeclaredTool(name: "selected")) {
                    try validate(
                        name: "selected", kind: "function", wire: wire, streaming: streaming, contract: &excluded)
                }
            }
        }
    }

    @Test("Unknown allowed references and an empty required subset fail before model output")
    func invalidSelections() throws {
        for wire in [ProviderToolContract.Wire.responses, .chatCompletions] {
            for (mode, names) in [("auto", ["missing"]), ("required", []), ("invalid", ["selected"])] {
                #expect(throws: ProviderToolContract.Error.invalidRequest) {
                    _ = try ProviderToolContract(
                        wire: wire, requestBody: request(wire: wire, kind: "function", names: names, mode: mode))
                }
            }
        }
    }

    @Test("Chat allowed selections require their nested selection and identity objects")
    func malformedChatEnvelopes() throws {
        let choices: [[String: Any]] = [
            ["type": "allowed_tools"], ["type": "allowed_tools", "allowed_tools": []],
            [
                "type": "allowed_tools",
                "allowed_tools": ["mode": "auto", "tools": [["type": "function"]]],
            ],
        ]
        for choice in choices {
            #expect(throws: ProviderToolContract.Error.invalidRequest) {
                _ = try ProviderToolContract(wire: .chatCompletions, requestBody: chatJSONData(["tool_choice": choice]))
            }
        }
    }

    @Test("Allowed references require an exact nonempty name and valid optional namespace")
    func malformedReferences() throws {
        let fields: [[String: Any]] = [
            [:], ["name": ""], ["name": 42],
            ["name": "selected", "namespace": ""], ["name": "selected", "namespace": 42],
        ]
        for wire in [ProviderToolContract.Wire.responses, .chatCompletions] {
            var references: [[String: Any]] = [[:], ["type": "unknown", "name": "selected"]]
            references += fields.map { fields in
                wire == .responses
                    ? fields.merging(["type": "function"]) { _, value in value }
                    : ["type": "function", "function": fields]
            }
            for reference in references {
                let selection: [String: Any] = ["mode": "auto", "tools": [reference]]
                let choice: [String: Any] =
                    wire == .responses
                    ? selection.merging(["type": "allowed_tools"]) { _, value in value }
                    : ["type": "allowed_tools", "allowed_tools": selection]
                var root = try chatJSONObject(request(wire: wire, kind: "function", names: []))
                root["tool_choice"] = choice
                #expect(throws: ProviderToolContract.Error.invalidRequest) {
                    _ = try ProviderToolContract(wire: wire, requestBody: chatJSONData(root))
                }
            }
        }
    }

    @Test("Chat filtering reserves a plain excluded name for projection")
    func chatExcludedNameReservation() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: chatJSONData([
                "model": "route", "input": "Use only the namespace child",
                "tools": [
                    ["type": "function", "name": "run"],
                    ["type": "namespace", "name": "workspace", "tools": [["type": "function", "name": "run"]]],
                ],
                "tool_choice": [
                    "type": "allowed_tools", "mode": "auto",
                    "tools": [["type": "function", "namespace": "workspace", "name": "run"]],
                ],
            ]), targetModel: "xlarge")
        #expect(prepared.toolNameCatalog.declared.contains("run"))
        let projected = try OpenAIResponsesChatCompletions.project(
            responseBody: chatJSONData([
                "choices": [
                    [
                        "finish_reason": "tool_calls",
                        "message": [
                            "tool_calls": [
                                [
                                    "id": "call", "type": "function", "function": ["name": "run", "arguments": "{}"],
                                ]
                            ]
                        ],
                    ]
                ]
            ]), prepared: prepared)
        let output = try #require(chatJSONObject(projected)["output"] as? [[String: Any]])
        let call = try #require(output.first { $0["type"] as? String == "function_call" })
        #expect(call["name"] as? String == "run")
        #expect(call["namespace"] == nil)
    }

    private func request(
        wire: ProviderToolContract.Wire, kind: String, names: [String], mode: String = "auto"
    ) throws -> Data {
        let tools: [[String: Any]] = ["selected", "excluded"].map { name in
            wire == .responses ? ["type": kind, "name": name] : ["type": kind, kind: ["name": name]]
        }
        let references: [[String: Any]] = names.map { name in
            wire == .responses ? ["type": kind, "name": name] : ["type": kind, kind: ["name": name]]
        }
        let selection: [String: Any] = ["mode": mode, "tools": references]
        var choice: [String: Any] = ["type": "allowed_tools"]
        if wire == .responses {
            choice.merge(selection) { _, value in value }
        } else {
            choice["allowed_tools"] = selection
        }
        return try chatJSONData(["tools": tools, "tool_choice": choice])
    }

    private func validate(
        name: String,
        namespace: String? = nil,
        kind: String,
        wire: ProviderToolContract.Wire,
        streaming: Bool,
        contract: inout ProviderToolContract
    ) throws {
        var identity: [String: Any] = ["name": name, kind == "function" ? "arguments" : "input": "{}"]
        if let namespace { identity["namespace"] = namespace }
        var item: [String: Any]
        if wire == .responses {
            item = identity
            item["type"] = kind == "function" ? "function_call" : "custom_tool_call"
            item["id"] = "item"
            item["call_id"] = "call"
            if streaming {
                try contract.validateFrame(frame(["type": "response.output_item.added", "item": item]))
            } else {
                try contract.validateBuffered(chatJSONData(["output": [item]]))
            }
        } else {
            item = ["id": "call", "type": kind, kind: identity]
            if streaming {
                item["index"] = 0
                try contract.validateFrame(frame(["choices": [["index": 0, "delta": ["tool_calls": [item]]]]]))
                try contract.validateFrame(frame(["choices": [["index": 0, "finish_reason": "tool_calls"]]]))
            } else {
                try contract.validateBuffered(chatJSONData(["choices": [["message": ["tool_calls": [item]]]]]))
            }
        }
    }

    private func frame(_ payload: [String: Any]) throws -> ServerSentEventFrame {
        ServerSentEventFrame(event: nil, data: try chatJSONData(payload), terminal: false)
    }
}
