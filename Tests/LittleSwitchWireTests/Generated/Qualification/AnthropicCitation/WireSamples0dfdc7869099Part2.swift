// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/TextCitation
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 34d1068d239cbf4d5a4678bcddec4fdbdb304592f0949638890254a9b99bb8eb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples0dfdc7869099Part2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicCitation.missing-tag",
            input: """
                {}
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicCitation(wireJSON: json).wireJSON()
        }
    ]
}
