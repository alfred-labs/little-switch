import Foundation

/// Extracts the model-readable text of Codex inter-agent mail.
///
/// Tool-authored mail (spawn briefs, send_message corrections) carries its
/// text inside an `encrypted_content` part; on custom providers that field
/// holds the model-authored plaintext verbatim, mirroring Codex's own
/// all-or-nothing `plaintext_agent_message_content` except that the payload
/// is treated as readable.
package enum ResponsesAgentMail {
    package enum Field: String {
        case encryptedFunctionArguments = "encrypted_function_args"
    }

    private enum MessageTool: String {
        case spawn = "spawn_agent"
        case send = "send_message"
        case followup = "followup_task"
    }

    /// Codex treats an absent list as encrypted mail. An explicit empty list
    /// selects its DirectPlaintextMessage path for these collaboration tools.
    /// Preserve a provider's explicit encryption declaration without inspecting
    /// or changing its arguments; native OpenAI passthrough never uses this adapter.
    package static func encryptedArguments(_ item: [String: Any]) throws -> [String]? {
        if let value = item[Field.encryptedFunctionArguments.rawValue], !(value is NSNull) {
            guard let arguments = value as? [String] else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            return arguments
        }
        guard item["namespace"] as? String == "collaboration",
            let name = item["name"] as? String, MessageTool(rawValue: name) != nil
        else { return nil }
        return []
    }

    package static func textContent(_ value: Any?) -> String? {
        guard let parts = value as? [[String: Any]] else {
            return nil
        }
        let text = parts.compactMap { part -> String? in
            switch part["type"] as? String {
            case "input_text", "output_text":
                nonemptyResponsesString(part["text"])
            case "encrypted_content":
                nonemptyResponsesString(part["encrypted_content"])
            default:
                nil
            }
        }
        return text.isEmpty ? nil : text.joined(separator: "\n")
    }
}
