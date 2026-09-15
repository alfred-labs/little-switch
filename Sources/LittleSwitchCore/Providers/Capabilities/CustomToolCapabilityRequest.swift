import AsyncHTTPClient
import Foundation
import NIOCore

enum CustomToolCapabilityRequest {
    static let toolName = "littleswitch_custom_probe"

    static func make(
        template: HTTPClientRequest,
        modelID: String,
        wire: ProviderToolContract.Wire,
        marker: String,
        envelope: Bool,
        includeOptionalControl: Bool = true
    ) throws -> HTTPClientRequest {
        var request = HTTPClientRequest(url: template.url)
        request.method = .POST
        // Copy authentication and account routing only. Client session and body
        // headers have no place in a synthetic exchange.
        let permittedHeaders: Set<String> = [
            "authorization", "x-api-key", "api-key", "x-goog-api-key", "openai-organization", "openai-project",
        ]
        for header in template.headers where permittedHeaders.contains(header.name.lowercased()) {
            request.headers.add(name: header.name, value: header.value)
        }
        request.headers.add(name: "content-type", value: "application/json")
        request.headers.add(name: "accept", value: "application/json")
        let instruction = envelope ? "the input string field" : "the raw input"
        let prompt = "Call \(toolName) exactly once. Set \(instruction) to exactly this marker:\n\(marker)"
        let responses = wire == .responses
        var root: [String: Any] = [
            "model": modelID, "stream": false, "tool_choice": selection(responses: responses, envelope: envelope),
            responses ? "max_output_tokens" : "max_tokens": 256,
            responses ? "input" : "messages": [["role": "user", "content": prompt]],
            "tools": [declaration(responses: responses, envelope: envelope)],
        ]
        if responses { root["store"] = false }
        if includeOptionalControl {
            switch optionalControl(template: template, wire: wire) {
            case "reasoning": root["reasoning"] = ["effort": "minimal"]
            case "thinking": root["thinking"] = ["type": "disabled"]
            default: break
            }
        }
        request.body = .bytes(ByteBuffer(bytes: try WireJSONCompatibility.data(root)))
        return request
    }

    static func optionalControl(template: HTTPClientRequest, wire: ProviderToolContract.Wire) -> String? {
        if wire == .responses { return "reasoning" }
        guard wire == .chatCompletions, let host = URL(string: template.url)?.host?.lowercased() else { return nil }
        return host == "z.ai" || host.hasSuffix(".z.ai") ? "thinking" : nil
    }

    private static func selection(responses: Bool, envelope: Bool) -> [String: Any] {
        // Some Responses providers restrict the generic "required" selector to
        // functions. Name the exact synthetic tool so custom support can be tested.
        let kind = envelope ? "function" : "custom"
        if responses { return ["type": kind, "name": toolName] }
        return ["type": kind, kind: ["name": toolName]]
    }

    private static func declaration(responses: Bool, envelope: Bool) -> [String: Any] {
        var fields: [String: Any] = ["name": toolName, "description": "Return the requested synthetic marker."]
        if envelope {
            fields["strict"] = true
            fields["parameters"] = [
                "type": "object", "properties": ["input": ["type": "string"]],
                "required": ["input"], "additionalProperties": false,
            ]
        } else {
            fields["format"] = ["type": "text"]
        }
        let kind = envelope ? "function" : "custom"
        if responses {
            fields["type"] = kind
            return fields
        }
        return ["type": kind, kind: fields]
    }
}
