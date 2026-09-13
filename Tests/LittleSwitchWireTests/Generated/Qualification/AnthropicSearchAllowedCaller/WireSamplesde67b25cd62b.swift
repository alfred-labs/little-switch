// Generated codec qualification. Do not edit.
// Source: AnthropicCountTokensRequest #/definitions/WebSearchTool20250305/properties/allowed_callers/items
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: 967c7ae1768ff5700b38a6cb5328610dc9e3a7ea26c787dde6f21985d2bd1106
// Projection SHA256: cb662fa62dc86582eeda7ba693d5a7b28cc3517c2496c67a1ce665a81b793aa2
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesde67b25cd62b {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicSearchAllowedCaller.enum:direct",
            input: """
                \"direct\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicSearchAllowedCaller(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchAllowedCaller.enum:code_execution_20250825",
            input: """
                \"code_execution_20250825\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicSearchAllowedCaller(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchAllowedCaller.enum:code_execution_20260120",
            input: """
                \"code_execution_20260120\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicSearchAllowedCaller(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchAllowedCaller.enum:code_execution_20260521",
            input: """
                \"code_execution_20260521\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicSearchAllowedCaller(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchAllowedCaller.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicSearchAllowedCaller(wireJSON: json).wireJSON()
        },
    ]
}
