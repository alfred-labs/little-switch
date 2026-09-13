import LittleSwitchWire

/// Correlation state extracted from a selected SDK item; it grants no visibility
/// or tool authority. Unknown items retain only the identity needed by Core.
struct ResponsesStreamWireMetadata {
    let id: String
    let type: String
    let function: ResponsesFunctionMetadata?
    let toolInput: String?

    init(_ item: OpenAIResponsesOutputItem) throws {
        switch item {
        case .message(let value):
            id = value.id
            type = value.type.rawValue
            toolInput = nil
        case .functionCall(let value):
            id = value.id ?? ""
            type = value.type.rawValue
            toolInput = value.arguments
        case .customToolCall(let value):
            id = value.id ?? ""
            type = value.type.rawValue
            toolInput = value.input
        case .reasoning(let value):
            id = value.id
            type = value.type.rawValue
            toolInput = nil
        case .webSearchCall(let value):
            id = value.id
            type = value.type.rawValue
            toolInput = nil
        case .toolSearchCall(let value):
            id = value.id
            type = value.type.rawValue
            toolInput = nil
        // swiftlint:disable:next pattern_matching_keywords
        case .unknown(let tag, let payload):
            // No SDK record describes a future item. Read only its Core
            // correlation identity; the opaque item is still not public output.
            do { id = try WireObject(payload).required("id") } catch {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            type = tag
            toolInput = nil
        }
        guard !id.isEmpty, !type.isEmpty else { throw OpenAIResponsesWebSearch.Error.invalidResponse }
        function = try responsesFunctionMetadata(item)
    }
}

extension OpenAIResponsesContentPart {
    var streamType: String {
        switch self {
        case .outputText(let value): value.type.rawValue
        case .refusal(let value): value.type.rawValue
        case .unknown(let type, _): type
        }
    }

    var streamText: String? {
        guard case .outputText(let value) = self else { return nil }
        return value.text
    }
}
