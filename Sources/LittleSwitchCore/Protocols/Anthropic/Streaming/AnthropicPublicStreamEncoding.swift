import Foundation
import LittleSwitchCommon
import LittleSwitchWire

func contentDeltaFrame(index: Int, deltaJSON: Data) throws -> Data {
    try publicStreamFrame(
        name: AnthropicContentBlockDeltaEventType.contentBlockDelta.rawValue,
        payload: AnthropicContentBlockDeltaEvent(
            delta: try publicStreamFragment(deltaJSON), index: JSONNumber(index), type: .contentBlockDelta
        ).wireJSON()
    )
}

func contentStopFrame(index: Int) throws -> Data {
    try publicStreamFrame(
        name: AnthropicContentBlockStopEventType.contentBlockStop.rawValue,
        payload: AnthropicContentBlockStopEvent(index: JSONNumber(index), type: .contentBlockStop).wireJSON()
    )
}

func publicUsage(inputTokens: Int, outputTokens: Int, webSearchRequests: Int) throws -> JSONValue {
    try publicUsage(
        usage: AnthropicUsage(inputTokens: inputTokens, outputTokens: outputTokens),
        webSearchRequests: webSearchRequests
    )
}

func publicUsage(
    usage: AnthropicUsage, outputTokens: Int? = nil, webSearchRequests: Int
) throws -> JSONValue {
    let fields = usageFields(usage, outputTokens: outputTokens)
    return try AnthropicPublicUsage(
        serverToolUse: AnthropicServerToolUsage(
            webFetchRequests: JSONNumber(0),
            webSearchRequests: JSONNumber(webSearchRequests)
        ),
        additionalFields: WireObject(fields.wireJSON()).additionalFields(excluding: [])
    ).wireJSON()
}

func publicTokenCount(_ value: JSONValue?) throws -> Int {
    guard let value, !value.isNull else { return 0 }
    guard let number = value.numberLiteral else { throw AnthropicWebSearch.Error.invalidMessage }
    return try anthropicTokenCount(number)
}

func publicStreamFragment(_ data: Data?) throws -> JSONValue {
    try AnthropicWebSearch.fragmentObject(from: data)
}

func publicStreamObject(_ data: Data) throws -> [String: JSONValue] {
    try AnthropicWebSearch.object(from: data)
}

func publicStreamData(_ value: JSONValue) throws -> Data {
    try value.serializedData()
}

func publicStreamData(_ value: [String: JSONValue]) throws -> Data {
    try anthropicJSON(value).serializedData()
}

func publicStreamFrame(name: String, payload: JSONValue) throws -> Data {
    var frame = Data("event: \(name)\ndata: ".utf8)
    frame.append(try publicStreamData(payload))
    frame.append(Data("\n\n".utf8))
    return frame
}
