import Foundation
import LittleSwitchWire

enum CustomToolCapabilityResponse {
    enum Outcome: Sendable { case matched, unusable, inconclusive, optionalControlRejected }

    static let maximumBytes = 64 * 1_024

    static func classify(
        body: Data,
        status: Int,
        wire: ProviderToolContract.Wire,
        marker: String,
        envelope: Bool,
        optionalControl: String? = nil
    ) -> Outcome {
        guard body.count <= maximumBytes, let root = try? WireJSONCompatibility.fields(body) else {
            return .inconclusive
        }
        guard (200..<300).contains(status) else {
            if let optionalControl, optionalRejection(root: root, status: status, control: optionalControl) {
                return .optionalControlRejected
            }
            return !envelope && customRejection(root: root, status: status) ? .unusable : .inconclusive
        }
        guard root["error"] == nil || root["error"] is NSNull else { return .inconclusive }
        let usage = root["usage"] as? [String: Any]
        if let tokens = usage?[wire == .responses ? "output_tokens" : "completion_tokens"] {
            guard let count = integer(tokens), count >= 0, count < 256 else { return .inconclusive }
        }
        switch wire {
        case .responses: return responses(root: root, marker: marker, envelope: envelope)
        case .chatCompletions: return chat(root: root, marker: marker, envelope: envelope)
        case .anthropic: return .inconclusive
        }
    }

    private static func responses(root: [String: Any], marker: String, envelope: Bool) -> Outcome {
        guard root["status"] as? String == "completed", let output = root["output"] as? [[String: Any]] else {
            return .inconclusive
        }
        let calls = output.filter { $0["type"] as? String != "message" && $0["type"] as? String != "reasoning" }
        guard !calls.isEmpty else { return .unusable }
        guard calls.count == 1, let call = calls.first,
            call["type"] as? String == (envelope ? "function_call" : "custom_tool_call"),
            call["status"] == nil || call["status"] as? String == "completed",
            let callID = call["call_id"] as? String, !callID.isEmpty
        else { return .inconclusive }
        return matches(call: call, marker: marker, envelope: envelope)
    }

    private static func chat(root: [String: Any], marker: String, envelope: Bool) -> Outcome {
        guard let choices = root["choices"] as? [[String: Any]], choices.count == 1, let choice = choices.first,
            let reason = choice["finish_reason"] as? String, reason == "tool_calls" || reason == "stop",
            let message = choice["message"] as? [String: Any], message["role"] as? String == "assistant"
        else { return .inconclusive }
        guard message["function_call"] == nil || message["function_call"] is NSNull else { return .inconclusive }
        let supplied = message["tool_calls"]
        if supplied == nil || supplied is NSNull { return reason == "stop" ? .unusable : .inconclusive }
        guard let calls = supplied as? [[String: Any]] else { return .inconclusive }
        guard !calls.isEmpty else { return reason == "stop" ? .unusable : .inconclusive }
        let kind = envelope ? "function" : "custom"
        guard reason == "tool_calls", calls.count == 1, let call = calls.first, call["type"] as? String == kind,
            let callID = call["id"] as? String, !callID.isEmpty, let fields = call[kind] as? [String: Any]
        else { return .inconclusive }
        return matches(call: fields, marker: marker, envelope: envelope)
    }

    private static func matches(call: [String: Any], marker: String, envelope: Bool) -> Outcome {
        guard call["name"] as? String == CustomToolCapabilityRequest.toolName,
            call["namespace"] == nil || call["namespace"] is NSNull,
            let input = call[envelope ? "arguments" : "input"] as? String
        else { return .inconclusive }
        let decoded = envelope ? try? CustomToolInputEnvelope.decode(input) : input
        return decoded == marker ? .matched : .inconclusive
    }

    private static func customRejection(root: [String: Any], status: Int) -> Bool {
        guard status == 400 || status == 422, let error = root["error"] as? [String: Any],
            let message = (error["message"] as? String)?.lowercased()
        else { return false }
        let parameter = (error["param"] as? String)?.lowercased() ?? ""
        let identifiesType = parameter == "tools[0].type" || message.contains("tools[0].type")
        let code = error["code"] as? String ?? error["code"].flatMap(integer).map(String.init)
        if code == "1214", identifiesType, message.contains("type is illegal") { return true }
        return identifiesType && message.contains("custom")
            && (message.contains("not supported") || message.contains("unsupported")
                || message.contains("invalid value"))
    }

    private static func integer(_ value: Any) -> Int? {
        guard let json = value as? JSONValue, case .numberLiteral(let number) = json else { return nil }
        return try? number.integerValue()
    }

    private static func optionalRejection(root: [String: Any], status: Int, control: String) -> Bool {
        guard status == 400 || status == 422, let error = root["error"] as? [String: Any],
            let message = (error["message"] as? String)?.lowercased()
        else { return false }
        let parameters = control == "reasoning" ? ["reasoning", "reasoning.effort"] : ["thinking", "thinking.type"]
        let identifiesControl: Bool
        if let parameter = (error["param"] as? String)?.lowercased() {
            identifiesControl = parameters.contains(parameter)
        } else {
            identifiesControl = parameters.contains { name in
                message.contains("parameter: '\(name)'") || message.contains("parameter: \"\(name)\"")
                    || message == "unrecognized request argument supplied: \(name)"
            }
        }
        guard identifiesControl else { return false }
        let code = error["code"] as? String ?? ""
        return ["unsupported_parameter", "unknown_parameter", "unsupported_value", "invalid_value"].contains(code)
            || [
                "unsupported parameter", "unknown parameter", "unrecognized request argument", "not supported",
                "unsupported value", "invalid value",
            ]
            .contains(where: message.contains)
    }
}
