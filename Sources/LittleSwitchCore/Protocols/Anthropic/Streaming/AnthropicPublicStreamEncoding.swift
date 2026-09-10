import Foundation

func contentDeltaFrame(index: Int, deltaJSON: Data) throws -> Data {
    try publicStreamFrame(
        name: "content_block_delta",
        payload: [
            "type": "content_block_delta",
            "index": index,
            "delta": try publicStreamObject(deltaJSON),
        ]
    )
}

func contentStopFrame(index: Int) throws -> Data {
    try publicStreamFrame(
        name: "content_block_stop",
        payload: ["type": "content_block_stop", "index": index]
    )
}

func publicUsage(
    inputTokens: Int,
    outputTokens: Int,
    webSearchRequests: Int
) -> [String: Any] {
    publicUsage(
        usage: AnthropicUsage(
            inputTokens: inputTokens,
            outputTokens: outputTokens
        ),
        webSearchRequests: webSearchRequests
    )
}

func publicUsage(
    usage: AnthropicUsage,
    outputTokens: Int? = nil,
    webSearchRequests: Int
) -> [String: Any] {
    [
        "input_tokens": usage.inputTokens,
        "output_tokens": outputTokens ?? usage.outputTokens,
        "cache_creation_input_tokens": usage.cacheCreationInputTokens,
        "cache_read_input_tokens": usage.cacheReadInputTokens,
        "cache_creation": [
            "ephemeral_1h_input_tokens": usage.cacheCreationEphemeral1hInputTokens,
            "ephemeral_5m_input_tokens": usage.cacheCreationEphemeral5mInputTokens,
        ],
        "service_tier": usage.serviceTier.map { $0 as Any } ?? NSNull(),
        "server_tool_use": [
            "web_search_requests": webSearchRequests,
            "web_fetch_requests": 0,
        ],
    ]
}

func publicTokenCount(_ value: Any?) throws -> Int {
    guard let value = value as? Int, value >= 0 else {
        if value == nil || value is NSNull {
            return 0
        }
        throw AnthropicWebSearch.Error.invalidMessage
    }
    return value
}

func publicStreamFragment(_ data: Data?) throws -> Any {
    guard let data else {
        return NSNull()
    }
    do {
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    } catch {
        throw AnthropicWebSearch.Error.invalidMessage
    }
}

func publicStreamObject(_ data: Data) throws -> [String: Any] {
    do {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        return object
    } catch let error as AnthropicWebSearch.Error {
        throw error
    } catch {
        throw AnthropicWebSearch.Error.invalidMessage
    }
}

func publicStreamData(_ value: Any) throws -> Data {
    try AnthropicWebSearch.serialize(
        value,
        options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
    ) { value, options in
        try JSONSerialization.data(withJSONObject: value, options: options)
    }
}

func publicStreamFrame(
    name: String,
    payload: [String: Any]
) throws -> Data {
    var frame = Data("event: \(name)\ndata: ".utf8)
    frame.append(try publicStreamData(payload))
    frame.append(Data("\n\n".utf8))
    return frame
}
