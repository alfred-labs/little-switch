// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/ServerToolUseBlock/properties/name/compatibility/anthropic-incoming-server-tool-name/known
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 0256884472d43453981d722aaf99b4cf6fb8e448e657c9e96e2742daa727d3f1
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesc33778379c90 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicIncomingServerToolName.enum:web_search",
            input: """
                \"web_search\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicIncomingServerToolName(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicIncomingServerToolName.enum:web_fetch",
            input: """
                \"web_fetch\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicIncomingServerToolName(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicIncomingServerToolName.enum:code_execution",
            input: """
                \"code_execution\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicIncomingServerToolName(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicIncomingServerToolName.enum:bash_code_execution",
            input: """
                \"bash_code_execution\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicIncomingServerToolName(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicIncomingServerToolName.enum:text_editor_code_execution",
            input: """
                \"text_editor_code_execution\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicIncomingServerToolName(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicIncomingServerToolName.enum:tool_search_tool_regex",
            input: """
                \"tool_search_tool_regex\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicIncomingServerToolName(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicIncomingServerToolName.enum:tool_search_tool_bm25",
            input: """
                \"tool_search_tool_bm25\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicIncomingServerToolName(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicIncomingServerToolName.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicIncomingServerToolName(wireJSON: json).wireJSON()
        },
    ]
}
