// Generated codec qualification. Do not edit.
// Source: OpenAIResponseRequestBase #/definitions/ResponseCreateParamsBase
// SDK: openai 7.15.0
// Schema SHA256: d6c9260f36d822d1a881d033a223917ca6cbf8d9da4b7aa4f6a6cb7991b93f6d
// Projection SHA256: e792ddcde0ce7025c4ce0628b2e68b61dbef2416759663ac11c1a066fe8b4a9d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples3636bf1ff1e0 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesRoutingRequest.minimal",
            input: """
                {}
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesRoutingRequest(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRoutingRequest.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"model\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesRoutingRequest(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRoutingRequest.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesRoutingRequest(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRoutingRequest.null:model",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"model\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["model"])
        ) { json in
            return try OpenAIResponsesRoutingRequest(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRoutingRequest.collision",
            input: """
                {}
                """,
            expectedError: .init(.additionalFieldCollision, path: ["model"])
        ) { json in
            var value = try OpenAIResponsesRoutingRequest(wireJSON: json)
            value.additionalFields["model"] = .null
            return try value.wireJSON()
        },
    ]
}
