import Foundation

enum ResponsesOllamaCompactionImages {
    static func input(_ encoded: String) throws -> [String: Any] {
        guard let bytes = Data(base64Encoded: encoded), !bytes.isEmpty else {
            throw ResponsesCompactionError.invalidPayload
        }
        let mimeType: String
        if bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) {
            mimeType = "image/png"
        } else if bytes.starts(with: [255, 216, 255]) {
            mimeType = "image/jpeg"
        } else if isWebP(bytes) {
            mimeType = "image/webp"
        } else {
            throw ResponsesCompactionError.invalidPayload
        }
        return [
            "type": "input_image", "detail": "auto",
            "image_url": "data:\(mimeType);base64,\(bytes.base64EncodedString())",
        ]
    }

    private static func isWebP(_ bytes: Data) -> Bool {
        bytes.count >= 14 && bytes.starts(with: [82, 73, 70, 70])
            && bytes[8..<14].elementsEqual([87, 69, 66, 80, 86, 80])
    }
}
