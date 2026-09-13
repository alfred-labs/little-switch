// Generated codec qualification. Do not edit.
// Source: OpenAIChatMessage #/definitions/ChatCompletionAssistantMessageParam
// SDK: openai 7.15.0
// Schema SHA256: 1c8afefdf7eb6e33f75a1f7cd15678903eed24156ab3c3b87e81928bd51177de
// Projection SHA256: a676e4a96ec14a5c179123508486129b68b5862ef10610414b88454a498e89aa
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesd95b1e34a6b1Part2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatRequestAssistant.collision",
            input: """
                {
                  \"role\": \"assistant\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["content"])
        ) { json in
            var value = try OpenAIChatRequestAssistant(wireJSON: json)
            value.additionalFields["content"] = .null
            return try value.wireJSON()
        }
    ]
}
