import Foundation
import LittleSwitchWire

private typealias RequestKey = OpenAIResponsesRequestEnvelope.Key
private typealias DeclarationKey = CustomToolDeclarationContract.Key
private typealias DeclarationKind = CustomToolDeclarationContract.Kind
private typealias FormatKind = CustomToolDeclarationContract.FormatKind
private typealias CustomOutputKey = OpenAIResponsesInputCustomOutput.Key
private typealias CustomOutputType = OpenAIResponsesInputCustomOutputType
private typealias InputCustomKey = OpenAIResponsesInputCustomCall.Key
private typealias InputFunctionKey = OpenAIResponsesInputFunctionCall.Key
private typealias ChatCallKey = CustomToolChatContract.CallKey
private typealias ChatPayloadKey = CustomToolChatContract.PayloadKey
private typealias SchemaField = CustomToolInputEnvelope.SchemaField

/// Lowers only the transport copy. Original declarations (including grammar)
/// remain in the exchange manifest, never reconstructed from a function schema.
struct CustomToolRequestProjection {
    private let body: Data
    private let wire: ProviderToolContract.Wire
    private(set) var declarations: [CustomToolProjection.Identity: JSONValue] = [:]

    init(body: Data, wire: ProviderToolContract.Wire) {
        self.body = body
        self.wire = wire
    }

    static let parameters: JSONValue = .object([
        SchemaField.type.rawValue: .string(CustomToolInputEnvelope.SchemaType.object.rawValue),
        SchemaField.properties.rawValue: .object([
            CustomToolInputEnvelope.Field.input.rawValue: .object([
                SchemaField.type.rawValue: .string(CustomToolInputEnvelope.SchemaType.string.rawValue)
            ])
        ]),
        SchemaField.required.rawValue: .array([.string(CustomToolInputEnvelope.Field.input.rawValue)]),
        SchemaField.additionalProperties.rawValue: .boolean(false),
    ])

    mutating func project() throws -> Data {
        guard var root = try JSONValue.parse(body).object else { throw CustomToolProjection.Error.invalidRequest }
        if let tools = root[RequestKey.tools.rawValue]?.array {
            root[RequestKey.tools.rawValue] = .array(try tools.map { try declaration($0) })
        }
        guard !declarations.isEmpty else { return body }
        if let choice = root[RequestKey.toolChoice.rawValue] {
            root[RequestKey.toolChoice.rawValue] = try selection(choice)
        }
        if wire == .responses, let input = root[RequestKey.input.rawValue]?.array {
            root[RequestKey.input.rawValue] = .array(try input.map { try responseHistory($0) })
        }
        if wire == .chatCompletions, let messages = root[OpenAIChatRequestEnvelope.Key.messages.rawValue]?.array {
            root[OpenAIChatRequestEnvelope.Key.messages.rawValue] = .array(
                try messages.map { message in
                    guard var object = message.object,
                        let calls = object[CustomToolChatContract.MessageKey.toolCalls.rawValue]?.array
                    else { return message }
                    object[CustomToolChatContract.MessageKey.toolCalls.rawValue] = .array(
                        try calls.map { try chatHistory($0) })
                    return .object(object)
                })
        }
        return try JSONValue.object(root).serializedData()
    }

    private mutating func declaration(_ value: JSONValue, namespace: String? = nil) throws -> JSONValue {
        guard var object = value.object else { throw CustomToolProjection.Error.invalidRequest }
        if object[DeclarationKey.type.rawValue] == .string(DeclarationKind.namespace.rawValue), wire == .responses {
            guard let name = object[DeclarationKey.name.rawValue]?.string,
                let children = object[DeclarationKey.tools.rawValue]?.array
            else {
                throw CustomToolProjection.Error.invalidRequest
            }
            object[DeclarationKey.tools.rawValue] = .array(try children.map { try declaration($0, namespace: name) })
            return .object(object)
        }
        guard object[DeclarationKey.type.rawValue] == .string(DeclarationKind.custom.rawValue) else { return value }
        let source = wire == .chatCompletions ? object[DeclarationKey.custom.rawValue] : value
        guard let source, var fields = source.object, let name = fields[DeclarationKey.name.rawValue]?.string,
            !name.isEmpty
        else {
            throw CustomToolProjection.Error.invalidRequest
        }
        let identity = CustomToolProjection.Identity(name: name, namespace: namespace)
        guard declarations.updateValue(value, forKey: identity) == nil else {
            throw CustomToolProjection.Error.invalidRequest
        }
        let format = fields.removeValue(forKey: DeclarationKey.format.rawValue)
        if let format, format.object?[DeclarationKey.type.rawValue] == .string(FormatKind.grammar.rawValue) {
            let description = fields[DeclarationKey.description.rawValue]?.string ?? ""
            fields[DeclarationKey.description.rawValue] = .string(
                description
                    + "\nThe input string must follow this custom tool format (instructions, not constrained decoding):\n"
                    + (try format.serialized()))
        }
        fields[DeclarationKey.parameters.rawValue] = Self.parameters
        fields[DeclarationKey.strict.rawValue] = .boolean(true)
        if wire == .chatCompletions {
            object.removeValue(forKey: DeclarationKey.custom.rawValue)
            object[DeclarationKey.type.rawValue] = .string(DeclarationKind.function.rawValue)
            object[DeclarationKey.function.rawValue] = .object(fields)
        } else {
            fields[DeclarationKey.type.rawValue] = .string(DeclarationKind.function.rawValue)
            object = fields
        }
        return .object(object)
    }

    private func selection(_ value: JSONValue) throws -> JSONValue {
        guard var fields = value.object else { return value }
        if fields[DeclarationKey.type.rawValue] == .string(DeclarationKind.custom.rawValue) {
            if wire == .chatCompletions {
                guard let custom = fields.removeValue(forKey: DeclarationKey.custom.rawValue) else {
                    throw CustomToolProjection.Error.invalidRequest
                }
                fields[DeclarationKey.function.rawValue] = custom
            }
            fields[DeclarationKey.type.rawValue] = .string(DeclarationKind.function.rawValue)
        } else if fields[DeclarationKey.type.rawValue] == .string(DeclarationKind.allowedTools.rawValue) {
            if wire == .chatCompletions {
                guard var nested = fields[DeclarationKey.allowedTools.rawValue]?.object,
                    let tools = nested[DeclarationKey.tools.rawValue]?.array
                else {
                    throw CustomToolProjection.Error.invalidRequest
                }
                nested[DeclarationKey.tools.rawValue] = .array(try tools.map(selection))
                fields[DeclarationKey.allowedTools.rawValue] = .object(nested)
            } else if let tools = fields[DeclarationKey.tools.rawValue]?.array {
                fields[DeclarationKey.tools.rawValue] = .array(try tools.map(selection))
            }
        }
        return .object(fields)
    }

    private func responseHistory(_ value: JSONValue) throws -> JSONValue {
        guard var fields = value.object else { return value }
        if fields[InputCustomKey.type.rawValue] == .string(OpenAIResponsesInputCustomCallType.customToolCall.rawValue) {
            guard let input = fields.removeValue(forKey: InputCustomKey.input.rawValue)?.string,
                fields[InputFunctionKey.arguments.rawValue] == nil
            else {
                throw CustomToolProjection.Error.invalidRequest
            }
            fields[InputFunctionKey.type.rawValue] = .string(OpenAIResponsesInputFunctionCallType.functionCall.rawValue)
            fields[InputFunctionKey.arguments.rawValue] = .string(try CustomToolInputEnvelope.encode(input))
        } else if fields[CustomOutputKey.type.rawValue] == .string(CustomOutputType.customToolCallOutput.rawValue) {
            fields[OpenAIResponsesInputFunctionOutput.Key.type.rawValue] = .string(
                OpenAIResponsesInputFunctionOutputType.functionCallOutput.rawValue)
        }
        return .object(fields)
    }

    private func chatHistory(_ value: JSONValue) throws -> JSONValue {
        guard var fields = value.object,
            fields[ChatCallKey.type.rawValue] == .string(OpenAIChatRequestCustomCallType.custom.rawValue)
        else { return value }
        guard var custom = fields.removeValue(forKey: ChatCallKey.custom.rawValue)?.object,
            let input = custom.removeValue(forKey: ChatPayloadKey.input.rawValue)?.string,
            fields[ChatCallKey.function.rawValue] == nil, custom[ChatPayloadKey.arguments.rawValue] == nil
        else { throw CustomToolProjection.Error.invalidRequest }
        custom[ChatPayloadKey.arguments.rawValue] = .string(try CustomToolInputEnvelope.encode(input))
        fields[ChatCallKey.type.rawValue] = .string(OpenAIChatRequestFunctionCallType.function.rawValue)
        fields[ChatCallKey.function.rawValue] = .object(custom)
        return .object(fields)
    }
}
