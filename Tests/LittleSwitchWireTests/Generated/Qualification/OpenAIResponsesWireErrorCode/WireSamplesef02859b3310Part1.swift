// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseError/properties/code/compatibility/openairesponsesresponse-responseerror-code-openenum/known
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: e7bbacb6bd0149ef6d886363a8327b15222a1b9e222599ae9ad52eb455735d9a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesef02859b3310Part1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesWireErrorCode.enum:server_error",
            input: """
                \"server_error\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireErrorCode.enum:rate_limit_exceeded",
            input: """
                \"rate_limit_exceeded\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireErrorCode.enum:invalid_prompt",
            input: """
                \"invalid_prompt\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireErrorCode.enum:data_residency_mismatch",
            input: """
                \"data_residency_mismatch\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireErrorCode.enum:bio_policy",
            input: """
                \"bio_policy\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireErrorCode.enum:misalignment_policy_violation",
            input: """
                \"misalignment_policy_violation\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireErrorCode.enum:vector_store_timeout",
            input: """
                \"vector_store_timeout\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireErrorCode.enum:invalid_image",
            input: """
                \"invalid_image\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireErrorCode.enum:invalid_image_format",
            input: """
                \"invalid_image_format\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireErrorCode.enum:invalid_base64_image",
            input: """
                \"invalid_base64_image\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireErrorCode.enum:invalid_image_url",
            input: """
                \"invalid_image_url\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireErrorCode.enum:image_too_large",
            input: """
                \"image_too_large\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireErrorCode.enum:image_too_small",
            input: """
                \"image_too_small\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireErrorCode.enum:image_parse_error",
            input: """
                \"image_parse_error\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireErrorCode.enum:image_content_policy_violation",
            input: """
                \"image_content_policy_violation\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireErrorCode.enum:invalid_image_mode",
            input: """
                \"invalid_image_mode\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireErrorCode.enum:image_file_too_large",
            input: """
                \"image_file_too_large\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireErrorCode.enum:unsupported_image_media_type",
            input: """
                \"unsupported_image_media_type\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireErrorCode.enum:empty_image_file",
            input: """
                \"empty_image_file\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireErrorCode.enum:failed_to_download_image",
            input: """
                \"failed_to_download_image\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireErrorCode.enum:image_file_not_found",
            input: """
                \"image_file_not_found\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireErrorCode.enum:context_length_exceeded",
            input: """
                \"context_length_exceeded\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireErrorCode(wireJSON: json).wireJSON()
        },
    ]
}
