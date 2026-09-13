// Generated codec qualification. Do not edit.
// Source: AnthropicMessageParam #/definitions/ServerToolUseBlockParam/properties/name/compatibility/anthropic-anthropicmessageparam-servertooluseblockparam-name-openenum/known
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: ba813716dfa815906783146a8e8228fcb6c1eb917c7cedd79803b4981bc59975
// Projection SHA256: 6abd874dc6e8fa342a15ceea5075e38eb220ee0f057fa0099513fedf9ad1013d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples323c7a6400aa {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicInputServerToolName.enum:web_search",
            input: """
                \"web_search\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicInputServerToolName(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicInputServerToolName.enum:web_fetch",
            input: """
                \"web_fetch\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicInputServerToolName(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicInputServerToolName.enum:code_execution",
            input: """
                \"code_execution\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicInputServerToolName(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicInputServerToolName.enum:bash_code_execution",
            input: """
                \"bash_code_execution\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicInputServerToolName(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicInputServerToolName.enum:text_editor_code_execution",
            input: """
                \"text_editor_code_execution\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicInputServerToolName(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicInputServerToolName.enum:tool_search_tool_regex",
            input: """
                \"tool_search_tool_regex\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicInputServerToolName(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicInputServerToolName.enum:tool_search_tool_bm25",
            input: """
                \"tool_search_tool_bm25\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicInputServerToolName(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicInputServerToolName.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicInputServerToolName(wireJSON: json).wireJSON()
        },
    ]
}
