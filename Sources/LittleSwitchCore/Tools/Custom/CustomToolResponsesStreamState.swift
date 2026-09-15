import Foundation
import LittleSwitchWire

private typealias FunctionKey = OpenAIResponsesFunctionCall.Key
private typealias CustomKey = OpenAIResponsesCustomCall.Key
private typealias ItemEventKey = OpenAIResponsesOutputItemAddedEvent.Key
private typealias ArgumentsDeltaKey = OpenAIFunctionArgumentsDelta.Key
private typealias ArgumentsDoneKey = OpenAIFunctionArgumentsDone.Key
private typealias CustomInputKey = OpenAICustomInputDone.Key
private typealias ResponseEventKey = OpenAIResponsesCompletedEvent.Key
private typealias ResponseKey = OpenAIResponsesResponse.Key

struct CustomToolResponsesStreamState {
    struct Call {
        let item: JSONValue
        let outputIndex: Int
        var arguments = ""
        var input: String?
        var itemDone = false
    }
    var calls: [Data: Call] = [:]
    private var retainedBytes = 0

    mutating func consume(
        _ value: JSONValue, type: String, projection: CustomToolProjection, maximumBytes: Int
    ) throws -> JSONValue? {
        guard var root = value.object else { throw CustomToolProjection.Error.invalidResponse }
        let item = root[ItemEventKey.item.rawValue]
        let functionType = OpenAIResponsesFunctionCallType.functionCall.wireJSON()
        if let item, item.object?[FunctionKey.type.rawValue] == functionType, projection.adapts(item) {
            guard let itemID = item.object?[FunctionKey.id.rawValue]?.string, !itemID.isEmpty else {
                throw CustomToolProjection.Error.invalidResponse
            }
            let id = Data(itemID.utf8)
            if type == OpenAIResponsesOutputItemAddedEventType.responseOutputItemAdded.rawValue {
                guard calls.count < CustomToolStreamProjection.maximumCalls else {
                    throw CustomToolProjection.Error.limitExceeded
                }
                guard calls[id] == nil,
                    var fields = item.object,
                    let arguments = fields.removeValue(forKey: FunctionKey.arguments.rawValue)?.string,
                    fields[CustomKey.input.rawValue] == nil, let callID = fields[FunctionKey.callId.rawValue]?.string,
                    !callID.isEmpty,
                    let index = root[ItemEventKey.outputIndex.rawValue]?.integer, index >= 0,
                    !calls.values.contains(where: {
                        $0.outputIndex == index || $0.item.object?[FunctionKey.callId.rawValue] == .string(callID)
                    })
                else { throw CustomToolProjection.Error.invalidResponse }
                try charge(try item.serializedData().count, maximumBytes: maximumBytes)
                calls[id] = Call(item: item, outputIndex: index, arguments: arguments)
                fields[CustomKey.type.rawValue] = .string(OpenAIResponsesCustomCallType.customToolCall.rawValue)
                fields[CustomKey.input.rawValue] = .string("")
                root[ItemEventKey.item.rawValue] = .object(fields)
            } else {
                guard type == OpenAIResponsesOutputItemDoneEventType.responseOutputItemDone.rawValue,
                    let call = calls[id], !call.itemDone,
                    root[ItemEventKey.outputIndex.rawValue]?.integer == call.outputIndex
                else { throw CustomToolProjection.Error.invalidResponse }
                try complete(item: item, id: id, maximumBytes: maximumBytes)
                calls[id]?.itemDone = true
                root[ItemEventKey.item.rawValue] = try projection.restoreResponseItem(item)
            }
        }
        let itemID = root[ArgumentsDeltaKey.itemId.rawValue]?.string.map { Data($0.utf8) }
        try validateArgumentIdentity(.object(root), type: type)
        if type.hasPrefix("response.function_call_arguments."), let id = itemID, var call = calls[id] {
            try validateMetadata(value, item: call.item)
            guard root[ArgumentsDeltaKey.outputIndex.rawValue]?.integer == call.outputIndex, !call.itemDone else {
                throw CustomToolProjection.Error.invalidResponse
            }
            if type == OpenAIFunctionArgumentsDeltaType.responseFunctionCallArgumentsDelta.rawValue {
                guard call.input == nil, let delta = root[ArgumentsDeltaKey.delta.rawValue]?.string else {
                    throw CustomToolProjection.Error.invalidResponse
                }
                try charge(delta.utf8.count, maximumBytes: maximumBytes)
                call.arguments += delta
                calls[id] = call
                return nil
            }
            if type == OpenAIFunctionArgumentsDoneType.responseFunctionCallArgumentsDone.rawValue {
                guard let arguments = root.removeValue(forKey: ArgumentsDoneKey.arguments.rawValue)?.string,
                    call.input == nil
                else {
                    throw CustomToolProjection.Error.invalidResponse
                }
                try complete(arguments: arguments, call: &call, maximumBytes: maximumBytes)
                calls[id] = call
                root[CustomInputKey.type.rawValue] = .string(
                    OpenAICustomInputDoneType.responseCustomToolCallInputDone.rawValue)
                root[CustomInputKey.input.rawValue] = call.input.map(JSONValue.string)
            }
        }
        let snapshot = root[ResponseEventKey.response.rawValue]
        if var response = snapshot?.object, let output = response[ResponseKey.output.rawValue]?.array {
            var finalIDs: Set<Data> = []
            response[ResponseKey.output.rawValue] = .array(
                try output.enumerated().map { index, item in
                    guard
                        item.object?[FunctionKey.type.rawValue]
                            == .string(OpenAIResponsesFunctionCallType.functionCall.rawValue), projection.adapts(item)
                    else { return item }
                    guard let id = item.object?[FunctionKey.id.rawValue]?.string.map({ Data($0.utf8) }),
                        let call = calls[id],
                        call.outputIndex == index, call.itemDone, finalIDs.insert(id).inserted
                    else { throw CustomToolProjection.Error.invalidResponse }
                    try complete(item: item, id: id, maximumBytes: maximumBytes)
                    return try projection.restoreResponseItem(item)
                })
            if type == OpenAIResponsesCompletedEventType.responseCompleted.rawValue, finalIDs != Set(calls.keys) {
                throw CustomToolProjection.Error.invalidResponse
            }
            root[ResponseEventKey.response.rawValue] = try projection.restoreResponseMetadata(.object(response))
        } else if type == OpenAIResponsesCompletedEventType.responseCompleted.rawValue, !calls.isEmpty {
            throw CustomToolProjection.Error.invalidResponse
        }
        return .object(root)
    }

    private mutating func complete(item: JSONValue, id: Data, maximumBytes: Int) throws {
        guard var call = calls[id], let arguments = item.object?[FunctionKey.arguments.rawValue]?.string else {
            throw CustomToolProjection.Error.invalidResponse
        }
        try validateMetadata(item, item: call.item)
        try complete(arguments: arguments, call: &call, maximumBytes: maximumBytes)
        calls[id] = call
    }

    private mutating func complete(arguments: String, call: inout Call, maximumBytes: Int) throws {
        if let input = call.input {
            guard try CustomToolInputEnvelope.decode(arguments).utf8.elementsEqual(input.utf8) else {
                throw CustomToolProjection.Error.invalidResponse
            }
            return
        }
        guard call.arguments.isEmpty || call.arguments.utf8.elementsEqual(arguments.utf8) else {
            throw CustomToolProjection.Error.invalidResponse
        }
        try charge(arguments.utf8.count, maximumBytes: maximumBytes)
        let input = try CustomToolInputEnvelope.decode(arguments)
        try charge(input.utf8.count, maximumBytes: maximumBytes)
        call.arguments = arguments
        call.input = input
    }

    private func validateMetadata(_ value: JSONValue, item: JSONValue) throws {
        for key in [FunctionKey.name.rawValue, FunctionKey.namespace.rawValue, FunctionKey.callId.rawValue] {
            if let supplied = value.object?[key], supplied != .null, supplied != item.object?[key] {
                throw CustomToolProjection.Error.invalidResponse
            }
        }
    }

    private func validateArgumentIdentity(_ value: JSONValue, type: String) throws {
        guard type.hasPrefix("response.function_call_arguments."),
            let known = calls.first(where: {
                $0.value.outputIndex == value.object?[ArgumentsDeltaKey.outputIndex.rawValue]?.integer
            })
        else { return }
        guard value.object?[ArgumentsDeltaKey.itemId.rawValue]?.string.map({ Data($0.utf8) }) == known.key else {
            throw CustomToolProjection.Error.invalidResponse
        }
    }

    private mutating func charge(_ bytes: Int, maximumBytes: Int) throws {
        guard bytes <= maximumBytes - retainedBytes else { throw CustomToolProjection.Error.limitExceeded }
        retainedBytes += bytes
    }
}
