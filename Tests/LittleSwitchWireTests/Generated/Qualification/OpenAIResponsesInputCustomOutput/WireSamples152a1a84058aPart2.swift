// Generated codec qualification. Do not edit.
// Source: OpenAIResponseInput #/definitions/ResponseCustomToolCallOutput
// SDK: openai 7.15.0
// Schema SHA256: 870dcd8b84d9a4fcdb3a9435cdaad8e560c959041c4e6f699dea1d9fe1e66bce
// Projection SHA256: 4230e2dc659577df8c394911cf9483c11c8c6ecbe06f6662ac63fc0afd4e2df7
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples152a1a84058aPart2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesInputCustomOutput.collision",
            input: """
                {
                  \"call_id\": \"wire sample\",
                  \"output\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"custom_tool_call_output\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["call_id"])
        ) { json in
            var value = try OpenAIResponsesInputCustomOutput(wireJSON: json)
            value.additionalFields["call_id"] = .null
            return try value.wireJSON()
        }
    ]
}
