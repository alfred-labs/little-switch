import CoreFoundation
import Foundation

/// A versioned portable continuation; `encrypted_content` is the Responses wire field, not encryption.
package enum ResponsesCompactionPayload {
    package static func expand(item: [String: Any]) throws -> [[String: Any]]? {
        guard item["type"] as? String == "compaction",
            let text = item["encrypted_content"] as? String,
            let payload = try? ResponsesCompactionJSON.object(Data(text.utf8), error: .invalidPayload)
        else { return nil }
        switch payload["type"] as? String {
        case "little_switch_compaction":
            let (summary, retained) = try ownedContents(payload)
            let opaque = retained.filter { $0["type"] as? String == "compaction" }
            let ordinary = retained.filter { $0["type"] as? String != "compaction" }
            return opaque + [summaryMessage(summary)] + ordinary
        case "ollama_compaction":
            return try ResponsesOllamaCompactionPayload.expand(payload)
        default:
            return nil
        }
    }

    static func summaryMessage(_ summary: String) -> [String: Any] {
        ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": summary]]]
    }

    private static func ownedContents(_ payload: [String: Any]) throws -> (String, [[String: Any]]) {
        let legacyKeys: Set<String> = ["type", "version", "summary"]
        // Early gateway v1 checkpoints stored only the summary. An absent
        // retained field means that legacy shape; a malformed field is rejected.
        guard Set(payload.keys) == legacyKeys || Set(payload.keys) == legacyKeys.union(["retained"]),
            let version = payload["version"] as? NSNumber,
            CFGetTypeID(version) != CFBooleanGetTypeID(), version == 1,
            let summary = ResponsesCompactionJSON.nonempty(payload["summary"]),
            let retained = (payload["retained"] ?? [[String: Any]]()) as? [[String: Any]]
        else { throw ResponsesCompactionError.invalidPayload }
        for item in retained { try validateRetained(item) }
        return (summary, retained)
    }

    private static func validateRetained(_ item: [String: Any]) throws {
        let kind = try ResponsesCompactionJSON.kind(item, error: .invalidPayload)
        guard !["compaction_trigger", "item_reference"].contains(kind) else {
            throw ResponsesCompactionError.invalidPayload
        }
        if kind == "compaction" {
            guard let text = ResponsesCompactionJSON.nonempty(item["encrypted_content"]) else {
                throw ResponsesCompactionError.invalidPayload
            }
            let nested = try? ResponsesCompactionJSON.object(Data(text.utf8), error: .invalidPayload)
            guard !["little_switch_compaction", "ollama_compaction"].contains(nested?["type"] as? String ?? "") else {
                throw ResponsesCompactionError.invalidPayload
            }
        }
    }
}
