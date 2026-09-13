// Generated codec qualification. Do not edit.
// Source: OpenAIChatChunk #/definitions/ChatCompletionChunk/properties/object
// SDK: openai 7.15.0
// Schema SHA256: f98b2133df86bdc3c79961c442f51881a69a75aecf09e34ad49b3d1e60ee3b01
// Projection SHA256: 5f4dfcd450738652bdac5ce04a289dd77e58825193954b2705192e5363d8824e
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesfa3d2ed7ffa9 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatChunkObject.enum:chat.completion.chunk",
            input: """
                \"chat.completion.chunk\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatChunkObject(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatChunkObject.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIChatChunkObject(wireJSON: json).wireJSON()
        },
    ]
}
