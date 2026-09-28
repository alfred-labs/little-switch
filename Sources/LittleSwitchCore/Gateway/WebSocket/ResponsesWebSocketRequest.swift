import Foundation
import LittleSwitchWire

/// The queued request owns only its normalized JSON and correlation fields.
/// Prior request options never participate in reconstruction.
struct ResponsesWebSocketRequest: Sendable {
    private typealias RequestField = ResponsesWebSocketContract.RequestField
    private typealias EventKey = OpenAIResponsesCreatedEvent.Key
    private typealias InputKey = OpenAIResponsesRequestEnvelope.Key
    private static let inputField = Data(",\"\(InputKey.input.rawValue)\":".utf8)

    struct Envelope: Sendable {
        let fields: JSONObject
        let streamID: String?
        let previousResponseID: String?

        init(_ frame: Data, maximumBytes: Int) throws {
            guard frame.count <= maximumBytes else {
                throw ResponsesWebSocketFailure(
                    status: 413, code: "request_too_large", message: "WebSocket frame is too large")
            }
            guard let fields = try? WireCodec.decode(JSONValue.self, from: frame).value.object else {
                throw ResponsesWebSocketFailure(
                    status: 400, code: "invalid_request_error", message: "Invalid JSON object")
            }
            streamID = try Self.streamID(in: fields)
            if fields[EventKey.type.rawValue]?.string == ResponsesWebSocketContract.Event.steer.rawValue {
                throw ResponsesWebSocketFailure(
                    status: 400,
                    code: "steering_not_supported",
                    message: "Mid-turn steering is not supported",
                    streamID: streamID,
                    parameter: EventKey.type.rawValue)
            }
            guard fields[EventKey.type.rawValue]?.string == ResponsesWebSocketContract.Event.create.rawValue else {
                throw Self.invalid("Expected response.create", streamID: streamID, parameter: EventKey.type.rawValue)
            }
            previousResponseID = try Self.previousResponseID(in: fields, streamID: streamID)
            self.fields = fields
        }

        private static func streamID(in fields: JSONObject) throws -> String? {
            guard let value = fields[RequestField.streamID.rawValue] else { return nil }
            guard let name = value.string, (1...256).contains(name.utf8.count),
                name.utf8.allSatisfy({
                    (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                        || [45, 46, 95].contains($0)
                })
            else {
                throw ResponsesWebSocketFailure(
                    status: 400,
                    code: "invalid_stream_id",
                    message: "Invalid WebSocket stream_id",
                    parameter: RequestField.streamID.rawValue)
            }
            return name
        }

        private static func previousResponseID(in fields: JSONObject, streamID: String?) throws -> String? {
            guard let value = fields[RequestField.previousResponseID.rawValue], value != .null else { return nil }
            guard let identifier = value.string, !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw invalid(
                    "Invalid previous_response_id",
                    streamID: streamID,
                    parameter: RequestField.previousResponseID.rawValue)
            }
            return identifier
        }

        static func invalid(_ message: String, streamID: String?, parameter: String) -> ResponsesWebSocketFailure {
            .init(
                status: 400, code: "invalid_request_error", message: message, streamID: streamID, parameter: parameter)
        }
    }

    let streamID: String?
    let previousResponseID: String?
    private let options: Data
    let input: ResponsesWebSocketInput
    let generate: Bool
    let replacesHistory: Bool

    var correlationBytes: Int { (streamID?.utf8.count ?? 0) + (previousResponseID?.utf8.count ?? 0) }
    var retainedBytes: Int { options.count + input.data.count + correlationBytes }

    init(_ envelope: Envelope) throws {
        let streamID = envelope.streamID
        var fields = envelope.fields
        guard let model = fields[OpenAIResponsesRoutingRequest.Key.model.rawValue]?.string,
            !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw Envelope.invalid(
                "A nonempty model is required",
                streamID: streamID,
                parameter: OpenAIResponsesRoutingRequest.Key.model.rawValue)
        }
        if let conversation = fields[RequestField.conversation.rawValue], conversation != .null {
            throw Envelope.invalid(
                "Server conversation references are not supported",
                streamID: streamID,
                parameter: RequestField.conversation.rawValue)
        }
        let background = try Self.boolean(
            fields[RequestField.background.rawValue],
            nullable: true,
            streamID: streamID,
            parameter: RequestField.background.rawValue)
        if background == true {
            throw Envelope.invalid(
                "Background responses are not supported",
                streamID: streamID,
                parameter: RequestField.background.rawValue)
        }
        _ = try Self.boolean(
            fields[RequestField.stream.rawValue],
            nullable: true,
            streamID: streamID,
            parameter: RequestField.stream.rawValue)
        let requestedGeneration =
            try Self.boolean(
                fields[RequestField.generate.rawValue],
                streamID: streamID,
                parameter: RequestField.generate.rawValue) ?? true
        let prewarm = try Self.prewarm(in: fields, streamID: streamID)
        let input = try Self.input(fields[InputKey.input.rawValue], streamID: streamID)
        let triggers = input.indices.filter {
            input[$0].object?[OpenAIResponsesUserMessage.Key.type.rawValue]?.string
                == ResponsesWebSocketContract.Kind.compactionTrigger.rawValue
        }
        guard triggers.isEmpty || (triggers.count == 1 && triggers.first == input.indices.last) else {
            throw Envelope.invalid(
                "A compaction trigger must be unique and last",
                streamID: streamID,
                parameter: InputKey.input.rawValue)
        }
        generate = requestedGeneration && !prewarm
        replacesHistory = !triggers.isEmpty
        guard generate || !replacesHistory else {
            throw Envelope.invalid(
                "Warmup cannot perform compaction", streamID: streamID, parameter: InputKey.input.rawValue)
        }
        for key in [
            EventKey.type.rawValue, RequestField.streamID.rawValue, RequestField.previousResponseID.rawValue,
            RequestField.generate.rawValue, RequestField.background.rawValue, RequestField.conversation.rawValue,
        ] {
            fields[key] = nil
        }
        fields[RequestField.stream.rawValue] = true
        fields[InputKey.input.rawValue] = nil
        self.streamID = streamID
        previousResponseID = envelope.previousResponseID
        options = try JSONValue.object(fields).serializedData()
        self.input = try ResponsesWebSocketInput(input)
    }

    /// Calculate capacity before allocating a potentially large replay copy.
    func activeBytes(parent: ResponsesWebSocketHistoryCache.Entry?) -> Int {
        let combinedInputBytes = parent?.input.bytes(appending: input) ?? input.data.count
        return options.count + Self.inputField.count + combinedInputBytes * 2 + correlationBytes
    }

    func turn(input: ResponsesWebSocketInput) -> ResponsesWebSocketTurn {
        // Model and stream guarantee a nonempty object. Both fragments came
        // from the exact JSON encoder, so their outer delimiters are known.
        var body = Data()
        body.reserveCapacity(options.count + Self.inputField.count + input.data.count)
        body.append(options.dropLast())
        body.append(Self.inputField)
        body.append(input.data)
        body.append(0x7D)
        return ResponsesWebSocketTurn(
            id: UUID(),
            streamID: streamID,
            body: body,
            generate: generate,
            previousResponseID: previousResponseID,
            replacesHistory: replacesHistory)
    }

    private static func input(_ value: JSONValue?, streamID: String?) throws -> [JSONValue] {
        guard let value else { return [] }
        if let text = value.string {
            let part = OpenAIResponsesInputTextPart(text: text, type: .inputText)
            let message = OpenAIResponsesUserMessage(
                content: .variant2([try part.wireJSON()]), role: .user, type: .message)
            return try [message.wireJSON()]
        }
        guard let items = value.array, items.allSatisfy({ $0.object != nil }) else {
            throw Envelope.invalid(
                "Input must be text or an array of objects", streamID: streamID, parameter: InputKey.input.rawValue)
        }
        return items
    }

    private static func boolean(
        _ value: JSONValue?, nullable: Bool = false, streamID: String?, parameter: String
    ) throws -> Bool? {
        guard let value else { return nil }
        if nullable && value == .null { return nil }
        guard let boolean = value.boolean else {
            throw Envelope.invalid("Invalid boolean field", streamID: streamID, parameter: parameter)
        }
        return boolean
    }

    private static func prewarm(in fields: JSONObject, streamID: String?) throws -> Bool {
        guard let value = fields[RequestField.promptCacheOptions.rawValue] else { return false }
        guard let options = value.object else {
            throw Envelope.invalid(
                "Invalid prompt cache options",
                streamID: streamID,
                parameter: RequestField.promptCacheOptions.rawValue)
        }
        return try boolean(
            options[RequestField.prewarm.rawValue],
            streamID: streamID,
            parameter: RequestField.promptCacheOptions.rawValue + "." + RequestField.prewarm.rawValue) ?? false
    }
}
