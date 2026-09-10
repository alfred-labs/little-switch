import Foundation

/// Extracts the model-readable text of Codex inter-agent mail.
///
/// Tool-authored mail (spawn briefs, send_message corrections) carries its
/// text inside an `encrypted_content` part; on custom providers that field
/// holds the model-authored plaintext verbatim, mirroring Codex's own
/// all-or-nothing `plaintext_agent_message_content` except that the payload
/// is treated as readable.
package enum ResponsesAgentMail {
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
