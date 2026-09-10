import Foundation

extension OpenAIResponsesChatCompletions {
    package static func supportsZAIStreamingTools(modelID: String) -> Bool {
        let normalized = modelID.lowercased()
        return ["glm-4.6", "glm-4.7", "glm-5"].contains { family in
            normalized == family
                || normalized.hasPrefix("\(family).")
                || normalized.hasPrefix("\(family)-")
        }
    }
}
