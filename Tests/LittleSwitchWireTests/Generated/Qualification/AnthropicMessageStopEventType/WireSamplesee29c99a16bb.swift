// Generated codec qualification. Do not edit.
// Source: AnthropicStreamEvent #/definitions/RawMessageStopEvent/properties/type
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: dbd6e5861026de9cfec261747e3e988ce10802ae7c4bc163574250bae74b1547
// Projection SHA256: 0d9e0b9014adafc925c53da23919464724a3a92e25e9669c2a214afd3a25828e
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesee29c99a16bb {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicMessageStopEventType.enum:message_stop",
            input: """
                \"message_stop\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicMessageStopEventType(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageStopEventType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicMessageStopEventType(wireJSON: json).wireJSON()
        },
    ]
}
