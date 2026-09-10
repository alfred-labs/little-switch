import Foundation

package enum ResponsesChatCompletionsImageContent {
    package static func multipart(_ parts: [[String: Any]]) -> [[String: Any]]? {
        var content: [[String: Any]] = []
        for part in parts {
            switch part["type"] as? String {
            case "input_text", "output_text":
                guard let text = part["text"] as? String else {
                    return nil
                }
                content.append(["type": "text", "text": text])
            case "input_image":
                guard let url = part["image_url"] as? String, !url.isEmpty else {
                    return nil
                }
                content.append([
                    "type": "image_url",
                    "image_url": ["url": url],
                ])
            default:
                return nil
            }
        }
        return content.isEmpty ? nil : content
    }
}
