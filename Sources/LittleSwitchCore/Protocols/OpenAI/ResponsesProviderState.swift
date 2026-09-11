import CoreFoundation
import Foundation

/// Provider state travels with the durable Responses item, so switching models
/// or restarting the gateway never depends on an in-memory response-ID cache.
package enum ResponsesProviderState {
    package enum Error: Swift.Error, Equatable {
        case invalidState
    }

    package static func normalize(body: Data, providerID: UUID?) throws -> Data {
        var root = try responsesStreamObject(body)
        guard let input = root["input"] as? [[String: Any]] else { return body }
        var changed = false
        var normalized: [[String: Any]] = []
        for item in input {
            let expanded = try ResponsesCompactionPayload.expand(item: item)
            if expanded != nil { changed = true }
            for entry in expanded ?? [item] {
                if entry["type"] as? String == "reasoning" {
                    if let restored = try reasoning(entry, providerID: providerID) {
                        if NSDictionary(dictionary: restored) != NSDictionary(dictionary: entry) { changed = true }
                        normalized.append(restored)
                    } else {
                        changed = true
                    }
                } else if providerID != nil, expanded != nil, entry["type"] as? String == "compaction" {
                    // This checkpoint already carries a portable summary. Keep
                    // its original encrypted state only for a return to OpenAI.
                    changed = true
                } else if providerID != nil, entry["type"] as? String == "configuration_update" {
                    // A native backend's durable reasoning settings do not configure a custom model.
                    changed = true
                } else {
                    normalized.append(entry)
                }
            }
        }
        guard changed else { return body }
        root["input"] = normalized
        return try responsesStreamData(root)
    }

    package static func requiresNativeRecovery(_ body: Data) throws -> Bool {
        let root = try responsesStreamObject(body)
        for item in root["input"] as? [[String: Any]] ?? [] where item["type"] as? String == "compaction" {
            if try ResponsesCompactionPayload.expand(item: item) == nil { return true }
        }
        return false
    }

    package static func isForeignReasoning(_ item: [String: Any], providerID: UUID?) throws -> Bool {
        guard isReasoning(item) else { return false }
        return try reasoning(item, providerID: providerID) == nil
    }

    /// Rewrites only response output slots. Tool arguments and nested user data
    /// that happen to contain a `type: reasoning` object are never traversed.
    package static func tag(response body: Data, providerID: UUID) throws -> Data {
        guard var root = try? responsesStreamObject(body) else { return body }
        var changed = false
        if let item = root["item"] as? [String: Any], item["type"] as? String == "reasoning" {
            root["item"] = try tagged(item, providerID: providerID)
            changed = true
        }
        if let output = root["output"] as? [[String: Any]], output.contains(where: isReasoning) {
            root["output"] = try output.map { try isReasoning($0) ? tagged($0, providerID: providerID) : $0 }
            changed = true
        }
        if var response = root["response"] as? [String: Any] {
            if let output = response["output"] as? [[String: Any]], output.contains(where: isReasoning) {
                response["output"] = try output.map { try isReasoning($0) ? tagged($0, providerID: providerID) : $0 }
                root["response"] = response
                changed = true
            }
        }
        return try changed ? responsesStreamData(root) : body
    }

    private static func isReasoning(_ item: [String: Any]) -> Bool { item["type"] as? String == "reasoning" }

    package static func tagged(_ item: [String: Any], providerID: UUID) throws -> [String: Any] {
        var tagged = item
        let payload: [String: Any] = [
            "type": "little_switch_reasoning", "version": 1,
            "provider_id": providerID.uuidString, "item": item,
        ]
        // JSONSerialization always produces valid UTF-8.
        // swiftlint:disable:next optional_data_string_conversion
        tagged["encrypted_content"] = String(decoding: try responsesStreamData(payload), as: UTF8.self)
        return tagged
    }

    private static func reasoning(_ item: [String: Any], providerID: UUID?) throws -> [String: Any]? {
        let tagged = try taggedReasoning(item, providerID: providerID)
        if tagged.wasTagged { return tagged.item }
        guard providerID == nil else { return nil }
        // Old Ollama histories predate provenance tagging. Its short numeric
        // IDs are local counters, unlike OpenAI's opaque reasoning IDs.
        var suffix = (item["id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if suffix.hasPrefix("rs_") {
            suffix.removeFirst(3)
            if suffix.hasPrefix("resp_") { suffix.removeFirst(5) }
            if (1...6).contains(suffix.count), suffix.utf8.allSatisfy({ (48...57).contains($0) }) { return nil }
        }
        return item
    }

    /// Internal tool loops already contain admitted raw state as well as newly
    /// tagged output. Open only the latter; repeating ingress normalization
    /// would discard the raw state admitted for this provider on the first pass.
    package static func restoreTaggedReasoning(_ item: [String: Any], providerID: UUID?) throws -> [String: Any]? {
        try taggedReasoning(item, providerID: providerID).item
    }

    private static func taggedReasoning(
        _ item: [String: Any], providerID: UUID?
    ) throws -> (wasTagged: Bool, item: [String: Any]?) {
        let encrypted = item["encrypted_content"] as? String
        let payload = encrypted.flatMap { try? responsesStreamObject(Data($0.utf8)) }
        if let payload, payload["type"] as? String == "little_switch_reasoning" {
            guard let version = payload["version"] as? NSNumber,
                CFGetTypeID(version) != CFBooleanGetTypeID(), nonnegativeResponsesIndex(version) == 1,
                let identifier = payload["provider_id"] as? String, let origin = UUID(uuidString: identifier),
                let original = payload["item"] as? [String: Any], isReasoning(original)
            else { throw Error.invalidState }
            return (true, providerID == origin ? original : nil)
        }
        return (false, item)
    }
}
