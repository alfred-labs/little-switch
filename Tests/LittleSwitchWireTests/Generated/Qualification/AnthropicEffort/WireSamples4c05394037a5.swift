// Generated codec qualification. Do not edit.
// Source: AnthropicCountTokensRequest #/definitions/OutputConfig/properties/effort/type/0
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: 967c7ae1768ff5700b38a6cb5328610dc9e3a7ea26c787dde6f21985d2bd1106
// Projection SHA256: fec4acfe2c5e4e5e6da8e260eae299ff0b3652ffcec38e650f98234cfeb9699b
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples4c05394037a5 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicEffort.enum:low",
            input: """
                \"low\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicEffort(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicEffort.enum:medium",
            input: """
                \"medium\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicEffort(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicEffort.enum:high",
            input: """
                \"high\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicEffort(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicEffort.enum:xhigh",
            input: """
                \"xhigh\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicEffort(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicEffort.enum:max",
            input: """
                \"max\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicEffort(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicEffort.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicEffort(wireJSON: json).wireJSON()
        },
    ]
}
