import Foundation

package enum ModelImageInputRejection {
    package static func matches(status: Int, body: Data, hasImageInput: Bool) -> Bool {
        guard hasImageInput, status == 400 || status == 422,
            let root = try? WireJSONCompatibility.fields(body),
            let error = root["error"] as? [String: Any],
            let text = error["message"] as? String
        else { return false }
        let message = text.lowercased()
        if message.contains("messages.content.type is invalid, allowed values: ['text']") { return true }
        return message.contains("model does not support image")
            || message.contains("model does not support vision")
            || message.contains("image input is not supported by this model")
            || message.contains("image inputs are not supported by this model")
    }
}
