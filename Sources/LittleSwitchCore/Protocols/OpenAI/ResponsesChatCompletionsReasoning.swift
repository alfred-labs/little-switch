import CoreFoundation
import Foundation

/// Chat providers return replayable state under either spelling. Keep those
/// fields opaque to Responses clients and restore them only after the provider
/// provenance boundary has admitted this item for its original destination.
package enum ResponsesChatCompletionsReasoning {
    private static let keys: Set<String> = ["reasoning", "reasoning_content"]
    private static let carrierType = "little_switch_chat_reasoning"

    package static func fields(in message: [String: Any]) throws -> [String: String] {
        var fields: [String: String] = [:]
        for key in keys {
            guard let value = message[key], !(value is NSNull) else { continue }
            guard let value = value as? String else {
                throw OpenAIResponsesChatCompletions.Error.invalidResponse
            }
            fields[key] = value
        }
        return fields
    }

    package static func item(
        message: [String: Any], responseID: String, providerID: UUID? = nil
    ) throws -> [String: Any]? {
        let fields = try fields(in: message)
        guard !fields.isEmpty else { return nil }
        let payload: [String: Any] = [
            "type": carrierType, "version": 1,
            "data": try responsesStreamData(fields).base64EncodedString(),
        ]
        let encoded = try responsesStreamData(payload)
        // JSONSerialization always produces valid UTF-8. The base64 payload is
        // an opaque transport encoding, not an encryption or security boundary.
        // swiftlint:disable:next optional_data_string_conversion
        let encrypted = String(decoding: encoded, as: UTF8.self)
        let item: [String: Any] = [
            "id": "rs_\(responseID)", "type": "reasoning", "summary": [],
            "encrypted_content": encrypted,
        ]
        guard let providerID else { return item }
        return try ResponsesProviderState.tagged(item, providerID: providerID)
    }

    package static func fields(from item: [String: Any], providerID: UUID? = nil) throws -> [String: String]? {
        guard item["type"] as? String == "reasoning",
            let item = try ResponsesProviderState.restoreTaggedReasoning(item, providerID: providerID),
            let encrypted = item["encrypted_content"] as? String,
            let payload = try? responsesStreamObject(Data(encrypted.utf8)),
            payload["type"] as? String == carrierType
        else { return nil }
        guard let version = payload["version"] as? NSNumber,
            CFGetTypeID(version) != CFBooleanGetTypeID(), version == 1,
            let encoded = payload["data"] as? String,
            let decoded = Data(base64Encoded: encoded),
            let rawFields = try? responsesStreamObject(decoded),
            !rawFields.isEmpty, Set(rawFields.keys).isSubset(of: keys),
            let fields = rawFields as? [String: String]
        else { throw OpenAIResponsesChatCompletions.Error.invalidRequest }
        return fields
    }

    /// This is an egress copy after wire selection. Preserve the durable body
    /// for a later Chat retry and never send the Chat carrier as native state.
    package static func nativeRequestBody(_ body: Data, providerID: UUID? = nil) throws -> Data {
        var root = try responsesStreamObject(body)
        guard let input = root["input"] as? [[String: Any]] else { return body }
        var changed = false
        var restored: [[String: Any]] = []
        for item in input {
            guard item["type"] as? String == "reasoning" else {
                restored.append(item)
                continue
            }
            guard let admitted = try ResponsesProviderState.restoreTaggedReasoning(item, providerID: providerID),
                try fields(from: admitted) == nil
            else {
                changed = true
                continue
            }
            if NSDictionary(dictionary: admitted) != NSDictionary(dictionary: item) { changed = true }
            restored.append(admitted)
        }
        guard changed else { return body }
        root["input"] = restored
        return try responsesStreamData(root)
    }
}
