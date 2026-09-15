import Foundation
import LittleSwitchWire

package enum ResponsesImageInputProjection {
    package static let omissionText = "[Image omitted: this model cannot inspect image input.]"

    package struct Result: Equatable, Sendable {
        package let body: Data
        package let imageItemIndices: Set<Int>
        package let omittedImageCount: Int
    }

    package static func project(body: Data, acceptsImages: Bool) throws -> Result {
        let json = try WireCodec.decode(JSONValue.self, from: body).value
        guard var root = json.object, var items = root[OpenAIResponsesRequestEnvelope.Key.input.rawValue]?.array else {
            return Result(body: body, imageItemIndices: [], omittedImageCount: 0)
        }
        var indices: Set<Int> = []
        var omitted = 0
        for index in items.indices {
            let item = items[index]
            guard let key = contentKey(for: item), var fields = item.object, var parts = fields[key]?.array else {
                continue
            }
            for partIndex in parts.indices where isImage(parts[partIndex]) {
                indices.insert(index)
                if !acceptsImages {
                    parts[partIndex] = .object([
                        OpenAIResponsesUserMessage.Key.type.rawValue: .string(
                            OpenAIResponsesInputTextPartType.inputText.rawValue),
                        OpenAIResponsesInputTextPart.Key.text.rawValue: .string(omissionText),
                    ])
                    omitted += 1
                }
            }
            fields[key] = .array(parts)
            items[index] = .object(fields)
        }
        guard omitted > 0 else { return Result(body: body, imageItemIndices: indices, omittedImageCount: 0) }
        root[OpenAIResponsesRequestEnvelope.Key.input.rawValue] = .array(items)
        return Result(
            body: try WireCodec.encode(JSONValue.object(root)), imageItemIndices: indices, omittedImageCount: omitted)
    }

    static func contentKey(for item: JSONValue) -> String? {
        guard let fields = item.object else { return nil }
        switch fields[OpenAIResponsesUserMessage.Key.type.rawValue]?.string {
        case OpenAIResponsesUserMessageType.message.rawValue: return OpenAIResponsesUserMessage.Key.content.rawValue
        case OpenAIResponsesInputFunctionOutputType.functionCallOutput.rawValue,
            OpenAIResponsesInputCustomOutputType.customToolCallOutput.rawValue:
            return OpenAIResponsesInputFunctionOutput.Key.output.rawValue
        case nil where fields[OpenAIResponsesUserMessage.Key.role.rawValue]?.string != nil:
            return OpenAIResponsesUserMessage.Key.content.rawValue
        default: return nil
        }
    }

    static func imageCount(in item: JSONValue) -> Int {
        guard let key = contentKey(for: item), let parts = item.object?[key]?.array else { return 0 }
        return parts.filter(isImage).count
    }

    private static func isImage(_ part: JSONValue) -> Bool {
        part.object?[OpenAIResponsesInputTextPart.Key.type.rawValue]?.string
            == ResponsesImagePartContract.Kind.inputImage.rawValue
    }
}
