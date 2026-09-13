import Foundation
import LittleSwitchWire

struct ResponsesOllamaCompactionMessage: Sendable {
    let role: String
    let toolName: String
    let toolCallID: String
    private let content: String
    private let thinking: String
    private let images: [String]
    private let calls: [Data]

    init(_ value: [String: Any]) throws {
        guard
            Set(value.keys).isSubset(of: [
                "role", "content", "thinking", "images", "tool_calls", "tool_name", "tool_call_id",
            ])
        else { throw ResponsesCompactionError.invalidPayload }
        role = try Self.string(value["role"]).lowercased()
        guard ["user", "assistant", "system", "developer", "tool"].contains(role) else {
            throw ResponsesCompactionError.invalidPayload
        }
        content = try Self.string(value["content"])
        thinking = try Self.string(value["thinking"])
        toolName = try Self.string(value["tool_name"])
        toolCallID = try Self.string(value["tool_call_id"])
        images = try Self.array(value["images"])
        let records: [[String: Any]] = try Self.array(value["tool_calls"])
        calls = try records.map(ResponsesCompactionJSON.data)
    }

    func responsesItems(standalone: ResponsesOllamaStandaloneName?) throws -> [[String: Any]] {
        var result: [[String: Any]] = []
        if !thinking.isEmpty {
            result.append([
                "type": "reasoning", "id": "rs_resp_0",
                "summary": [["type": "summary_text", "text": thinking]],
            ])
        }
        if role == "tool" {
            result.append(try toolOutput(standalone: standalone))
        } else if !content.isEmpty || !images.isEmpty || calls.isEmpty {
            result.append(["type": "message", "role": role, "content": try contentValue()])
        }
        return try result + calls.map(Self.toolCall)
    }

    private static func toolCall(_ data: Data) throws -> [String: Any] {
        let call = try ResponsesCompactionJSON.object(data, error: .invalidPayload)
        guard let id = call["id"] as? String, ResponsesCompactionJSON.nonempty(id) != nil,
            let function = call["function"] as? [String: Any],
            let name = function["name"] as? String, ResponsesCompactionJSON.nonempty(name) != nil
        else { throw ResponsesCompactionError.invalidPayload }
        let arguments: [String: Any]
        if let raw = function["arguments"], !(raw is NSNull) {
            guard let object = raw as? [String: Any] else { throw ResponsesCompactionError.invalidPayload }
            arguments = object
        } else {
            arguments = [:]
        }
        if name == "tool_search" {
            return [
                "type": "tool_search_call", "call_id": id, "execution": "client", "status": "completed",
                "arguments": arguments,
            ]
        }
        return [
            "type": "function_call", "call_id": id, "name": name,
            "arguments": try ResponsesCompactionJSON.text(arguments),
        ]
    }

    private func toolOutput(standalone: ResponsesOllamaStandaloneName?) throws -> [String: Any] {
        if toolCallID.isEmpty {
            guard let standalone else { throw ResponsesCompactionError.invalidPayload }
            var result: [String: Any] = [
                "type": "function_call_output", "name": standalone.name, "output": try contentValue(),
            ]
            if !standalone.namespace.isEmpty { result["namespace"] = standalone.namespace }
            return result
        }
        if toolName == "tool_search" {
            guard images.isEmpty,
                let value = try? JSONValue.parse(Data(content.utf8)),
                let tools = WireJSONCompatibility.view(value) as? [[String: Any]]
            else { throw ResponsesCompactionError.invalidPayload }
            return [
                "type": "tool_search_output", "call_id": toolCallID, "execution": "client", "status": "completed",
                "tools": tools,
            ]
        }
        return ["type": "function_call_output", "call_id": toolCallID, "output": try contentValue()]
    }

    private func contentValue() throws -> Any {
        guard !images.isEmpty else { return content }
        var parts: [[String: Any]] = []
        if !content.isEmpty { parts.append(["type": "input_text", "text": content]) }
        return try parts + images.map(ResponsesOllamaCompactionImages.input)
    }

    static func string(_ value: Any?) throws -> String {
        guard let value, !(value is NSNull) else { return "" }
        guard let text = value as? String else { throw ResponsesCompactionError.invalidPayload }
        return text
    }

    static func array<Element>(_ value: Any?) throws -> [Element] {
        guard let value, !(value is NSNull) else { return [] }
        guard let array = value as? [Element] else { throw ResponsesCompactionError.invalidPayload }
        return array
    }
}
