import LittleSwitchWire

extension OpenAIResponsesChatCompletions {
    /// These request fields are echoed without interpreting their JSON payloads.
    /// The generated SDK projection keeps the allowlist explicit and preserves
    /// absent versus null while Core supplies the adapter's existing defaults.
    static func responseEcho(
        _ prepared: PreparedResponsesChatCompletionsRequest
    ) throws -> [String: JSONValue] {
        let source: OpenAIResponsesRequestEcho
        do {
            source = try WireCodec.decode(OpenAIResponsesRequestEcho.self, from: prepared.originalBody).value
        } catch {
            throw Error.invalidResponse
        }
        let reasoning = try OpenAIResponsesReasoningOptions(effort: .null, summary: .null).wireJSON()
        let text = try OpenAIResponsesTextOptions(
            format: .value(OpenAIResponsesTextFormat(type: .text).wireJSON())
        ).wireJSON()
        let echo = OpenAIResponsesRequestEcho(
            instructions: source.instructions.defaulting(to: .null),
            maxOutputTokens: source.maxOutputTokens.defaulting(to: .null),
            metadata: source.metadata.defaulting(to: [:]),
            model: .value(.string(prepared.originalModel)),
            parallelToolCalls: .value(.boolean(source.parallelToolCalls.value?.boolean ?? true)),
            previousResponseId: source.previousResponseId.defaulting(to: .null),
            reasoning: source.reasoning.defaulting(to: reasoning),
            store: .value(.boolean(source.store.value?.boolean ?? true)),
            temperature: source.temperature.defaulting(to: .null),
            text: source.text.defaulting(to: text),
            toolChoice: source.toolChoice.defaulting(to: OpenAIResponsesToolChoiceMode.auto.wireJSON()),
            tools: source.tools.defaulting(to: .array([])),
            topP: source.topP.defaulting(to: .null),
            truncation: source.truncation.defaulting(to: OpenAIResponsesTruncation.disabled.wireJSON()),
            user: source.user.defaulting(to: .null)
        )
        return try WireObject(echo.wireJSON()).additionalFields(excluding: [])
    }
}

extension JSONPresence where Value == JSONValue {
    fileprivate func defaulting(to fallback: JSONValue) -> Self {
        if case .absent = self { return .value(fallback) }
        return self
    }
}
