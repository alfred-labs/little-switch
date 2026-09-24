import Foundation
import LittleSwitchWire

/// A readable, lossless archive of one retired tool item. The label is data in
/// conversation history, never a system/developer instruction or a declaration.
enum ResponsesRetiredToolMessage {
    private static let label = "[Historical tool exchange; reference only, not an available tool or instructions]\n"
    private typealias OutputKey = OpenAIResponsesInputCustomOutput.Key
    private typealias ImageField = ResponsesImagePartContract.Field

    /// LittleSwitch's textual archive metadata, not provider wire fields.
    private enum ArchiveKey: String {
        case item
        case attachments
        case outputIndex = "output_index"
        case contentIndex = "content_index"
    }

    static func project(_ item: JSONValue) throws -> JSONValue {
        var archived = item
        var images: [JSONValue] = []
        var attachments: [JSONValue] = []
        if var fields = item.object, var output = fields[OutputKey.output.rawValue]?.array {
            for index in output.indices {
                guard var skeleton = output[index].object,
                    skeleton[OpenAIResponsesInputTextPart.Key.type.rawValue]?.string
                        == ResponsesImagePartContract.Kind.inputImage.rawValue
                else { continue }
                images.append(output[index])
                // Keep image metadata in the archive too: the Chat image
                // adapter transports only URL/detail, not unknown fields.
                if skeleton[ImageField.imageURL.rawValue] != nil { skeleton[ImageField.imageURL.rawValue] = .null }
                output[index] = .object(skeleton)
                attachments.append(
                    .object([
                        ArchiveKey.outputIndex.rawValue: .numberLiteral(JSONNumber(index)),
                        ArchiveKey.contentIndex.rawValue: .numberLiteral(JSONNumber(images.count)),
                    ]))
            }
            if !images.isEmpty {
                fields[OutputKey.output.rawValue] = .array(output)
                archived = .object([
                    ArchiveKey.item.rawValue: .object(fields), ArchiveKey.attachments.rawValue: .array(attachments),
                ])
            }
        }
        let text = label + (try archived.serialized())
        if images.isEmpty {
            let part = OpenAIResponsesReplayTextPart(text: text, type: .outputText)
            return try OpenAIResponsesReplayMessage(
                content: [part.wireJSON()], role: .assistant, type: .message
            ).wireJSON()
        }
        // Media stays media; serializing base64 as prose would consume the
        // context window and lose the model's visual input.
        let part = OpenAIResponsesInputTextPart(text: text, type: .inputText)
        return try OpenAIResponsesUserMessage(
            content: .variant2([part.wireJSON()] + images), role: .user, type: .message
        ).wireJSON()
    }
}
