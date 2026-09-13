// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/WebSearchResultBlock/properties/type
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 34d1068d239cbf4d5a4678bcddec4fdbdb304592f0949638890254a9b99bb8eb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesfbe0453a45d3 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicWebSearchResultType.enum:web_search_result",
            input: """
                \"web_search_result\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicWebSearchResultType(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchResultType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicWebSearchResultType(wireJSON: json).wireJSON()
        },
    ]
}
