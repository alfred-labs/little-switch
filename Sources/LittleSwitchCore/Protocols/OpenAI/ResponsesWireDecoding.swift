import Foundation
import LittleSwitchWire

/// Wire failures become the existing Core protocol error at the owned adapter boundary.
func responsesWireDecode<Value: WireCodable>(_ type: Value.Type, from data: Data) throws -> Value {
    try responsesWireDocument(type, from: data).value
}

func responsesWireDocument<Value: WireCodable>(_ type: Value.Type, from data: Data) throws -> WireDocument<Value> {
    do {
        return try WireCodec.decode(type, from: data)
    } catch {
        throw OpenAIResponsesWebSearch.Error.invalidResponse
    }
}

func responsesWireDecode<Value: WireCodable>(_ type: Value.Type, json: JSONValue) throws -> Value {
    do {
        return try Value(wireJSON: json)
    } catch {
        throw OpenAIResponsesWebSearch.Error.invalidResponse
    }
}

func responsesWireIndex(_ number: JSONNumber) throws -> Int {
    guard let value: Int = try? number.integerValue(), value >= 0 else {
        throw OpenAIResponsesWebSearch.Error.invalidResponse
    }
    return value
}

func responsesWireUsage(_ usage: OpenAIResponsesWireUsage?) throws -> ResponsesUsage {
    let input = try usage?.inputTokens.map(responsesWireIndex) ?? 0
    let output = try usage?.outputTokens.map(responsesWireIndex) ?? 0
    return try ResponsesUsage(
        inputTokens: input,
        outputTokens: output,
        cachedInputTokens: usage?.inputTokensDetails.value.map { try responsesWireIndex($0.cachedTokens) } ?? 0,
        cacheWriteInputTokens: usage?.inputTokensDetails.value?.cacheWriteTokens.map(responsesWireIndex) ?? 0,
        reasoningOutputTokens: usage?.outputTokensDetails.value.map { try responsesWireIndex($0.reasoningTokens) } ?? 0,
        totalTokens: usage?.totalTokens.map(responsesWireIndex)
    )
}

func responsesWireTerminal(_ status: OpenAIResponsesStatus?) throws -> ResponsesStreamTerminal {
    switch status {
    case .none, .completed: return .completed
    case .incomplete: return .incomplete
    case .failed: return .failed
    default: throw OpenAIResponsesWebSearch.Error.invalidResponse
    }
}

func responsesWireJSON(_ fields: [String: JSONValue]) -> JSONValue {
    .object(.init(uniqueKeysWithValues: fields.sorted { $0.key < $1.key }))
}

func nonemptyResponsesString(_ value: JSONValue?) -> String? {
    guard let value = value?.string, !value.isEmpty else { return nil }
    return value
}
