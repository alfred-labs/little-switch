import Foundation
import LittleSwitchWire

/// Reshapes Responses turns that carry an image for providers whose
/// completion reserve mis-sizes them.
///
/// The provider sizes its completion reserve from an input estimate that does not
/// count image tokens, then validates the total against the context window
/// with those tokens counted, so the sum overflows by exactly the image's
/// token cost — a constant 402373 against a 400000-token window, whatever the
/// conversation's size. Two conditions drive it, and both must be answered:
/// `reasoning.effort` makes the provider ignore `max_output_tokens` and take
/// the reserve path, and without an explicit budget there is nothing else to
/// bound the completion. Dropping the effort field and naming a budget makes
/// the same request succeed, image read correctly, on turns from 5 to 448
/// items. Text turns are untouched, so their bodies stay byte-identical.
package enum ResponsesImageTurnCompatibility {
    /// Far above any Codex turn, far below the context windows these
    /// providers advertise (262k–400k tokens).
    package static let maximumOutputTokens = 32_768

    static func rewritten(wire object: JSONObject) throws -> JSONObject? {
        guard let rewritten = try rewritten(WireJSONCompatibility.fields(.object(object))) else { return nil }
        return try WireJSONCompatibility.value(rewritten).object
    }

    /// The request reshaped for an image turn, or nil when nothing applies.
    package static func rewritten(_ object: [String: Any]) -> [String: Any]? {
        guard containsImage(object["input"]) else {
            return nil
        }
        var rewritten = object
        var changed = false
        if let reasoning = effortless(object["reasoning"]) {
            rewritten["reasoning"] = reasoning
            changed = true
        }
        let declared = object["max_output_tokens"]
        if declared == nil || declared is NSNull {
            rewritten["max_output_tokens"] = maximumOutputTokens
            changed = true
        }
        return changed ? rewritten : nil
    }

    /// The reasoning block without its effort field, or nil when there is
    /// none to strip.
    private static func effortless(_ value: Any?) -> [String: Any]? {
        guard var reasoning = value as? [String: Any],
            reasoning["effort"] != nil
        else {
            return nil
        }
        reasoning.removeValue(forKey: "effort")
        return reasoning
    }

    private static func containsImage(_ input: Any?) -> Bool {
        guard let input, let items = (try? WireJSONCompatibility.value(input))?.array else {
            return false
        }
        return items.contains { ResponsesImageInputProjection.imageCount(in: $0) > 0 }
    }
}
