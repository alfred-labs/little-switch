import Foundation

/// Lowers client-executed Responses tool search to ordinary function calling.
/// Discovery remains in the client; replay is enough to rebuild the loaded set.
package enum OpenAIResponsesToolSearch {
    package enum Error: Swift.Error, Equatable {
        case invalidRequest
    }

    package static func prepare(
        body: Data,
        originalBody: Data? = nil
    ) throws -> PreparedResponsesToolSearchRequest? {
        guard var root = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw Error.invalidRequest
        }
        let tools = root["tools"] as? [[String: Any]] ?? []
        let input = root["input"] as? [[String: Any]] ?? []
        let declarations = tools.filter {
            $0["type"] as? String == "tool_search" && $0["execution"] as? String == "client"
        }
        let hasHistory = input.contains { isClientSearchItem($0) }
        let hasAdditionalTools = input.contains { $0["type"] as? String == "additional_tools" }
        guard !declarations.isEmpty || hasHistory || hasAdditionalTools else { return nil }
        guard declarations.count <= 1 else { throw Error.invalidRequest }

        let loaded = try input.filter {
            ($0["type"] as? String == "tool_search_output" && isClientSearchItem($0))
                || $0["type"] as? String == "additional_tools"
        }
        .flatMap { item -> [[String: Any]] in
            guard let tools = item["tools"] as? [[String: Any]] else { throw Error.invalidRequest }
            return tools
        }
        let catalog = try OpenAIResponsesToolSearchCatalog(
            tools: tools.filter { $0["type"] as? String != "tool_search" || $0["execution"] as? String != "client" },
            loaded: loaded,
            deferUndiscovered: !declarations.isEmpty || hasHistory
        )
        let contract: ResponsesClientToolSearchContract? =
            !declarations.isEmpty || hasHistory
            ? ResponsesClientToolSearchContract(wireName: reservedName(tools: tools + loaded, input: input)) : nil
        var inferenceTools = catalog.tools
        if let declaration = declarations.first, let contract {
            guard let description = declaration["description"] as? String,
                let parameters = declaration["parameters"] as? [String: Any]
            else { throw Error.invalidRequest }
            inferenceTools.insert(
                [
                    "type": "function", "name": contract.wireName,
                    "description": description, "parameters": parameters,
                ], at: 0)
        }
        root["tools"] = inferenceTools
        if root["input"] is [[String: Any]] {
            root["input"] = try input.map { try loweredItem($0, contract: contract) }
        }
        if let choice = root["tool_choice"] as? [String: Any], choice["type"] as? String == "tool_search" {
            guard !declarations.isEmpty, let contract else { throw Error.invalidRequest }
            root["tool_choice"] = ["type": "function", "name": contract.wireName]
        }
        return PreparedResponsesToolSearchRequest(
            upstreamBody: try encode(root),
            originalBody: originalBody ?? body,
            contract: contract
        )
    }

    private static func isClientSearchItem(_ item: [String: Any]) -> Bool {
        ["tool_search_call", "tool_search_output"].contains(item["type"] as? String ?? "")
            && item["execution"] as? String == "client"
    }

    private static func loweredItem(
        _ item: [String: Any],
        contract: ResponsesClientToolSearchContract?
    ) throws -> [String: Any] {
        if item["type"] as? String == "additional_tools" {
            guard item["role"] as? String == "developer", let tools = item["tools"] as? [[String: Any]] else {
                throw Error.invalidRequest
            }
            return [
                "type": "message", "role": "developer",
                "content": [
                    ["type": "input_text", "text": try encodedString(["tools": tools])]
                ],
            ]
        }
        guard isClientSearchItem(item) else { return item }
        guard let contract, let callID = nonemptyResponsesString(item["call_id"]) else { throw Error.invalidRequest }
        if item["type"] as? String == "tool_search_call" {
            guard let arguments = item["arguments"] as? [String: Any] else { throw Error.invalidRequest }
            return [
                "type": "function_call", "call_id": callID, "name": contract.wireName,
                "arguments": try encodedString(arguments),
            ]
        }
        guard let tools = item["tools"] as? [[String: Any]],
            item["status"] == nil || item["status"] as? String == "completed"
        else { throw Error.invalidRequest }
        return [
            "type": "function_call_output", "call_id": callID,
            "output": try encodedString(["tools": tools]),
        ]
    }

    private static func reservedName(tools: [[String: Any]], input: [[String: Any]]) -> String {
        let flattened = ResponsesToolNamespaces.flatten(tools: tools)
        var names = Set(flattened.tools.compactMap { $0["name"] as? String })
        for item in input where item["type"] as? String == "function_call" {
            guard let name = item["name"] as? String else { continue }
            if let namespace = nonemptyResponsesString(item["namespace"]) {
                names.insert(
                    ResponsesToolNamespaces.replayName(bindings: flattened.bindings, namespace: namespace, name: name))
            } else {
                names.insert(name)
            }
        }
        let base = "little_switch_tool_search"
        var candidate = base
        var suffix = 2
        while names.contains(candidate) {
            candidate = "\(base)_\(suffix)"
            suffix += 1
        }
        return candidate
    }

    static func encode(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private static func encodedString(_ value: Any) throws -> String {
        // JSONSerialization emits valid UTF-8; this conversion cannot lose data.
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: try encode(value), as: UTF8.self)
    }
}
