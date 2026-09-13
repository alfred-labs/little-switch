import LittleSwitchWire

/// The gateway owns this private tool input contract; it is not an SDK record.
enum AnthropicPrivateSearchInput {
    enum Key: String { case query }

    private enum PropertySchemaKey: String { case type, description }

    static func value(query: String) -> JSONValue {
        anthropicJSON([Key.query.rawValue: .string(query)])
    }

    static var schema: AnthropicToolInputSchema {
        AnthropicToolInputSchema(
            properties: .value(
                anthropicJSON([
                    Key.query.rawValue: anthropicJSON([
                        PropertySchemaKey.type.rawValue: "string",
                        PropertySchemaKey.description.rawValue: "The search query to look up on the web",
                    ])
                ])),
            required: .value([Key.query.rawValue]),
            type: .object
        )
    }
}
