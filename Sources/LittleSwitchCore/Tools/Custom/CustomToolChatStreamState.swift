import Foundation
import LittleSwitchWire

private typealias CompletionKey = CustomToolChatContract.CompletionKey
private typealias ChoiceKey = CustomToolChatContract.ChoiceKey
private typealias MessageKey = CustomToolChatContract.MessageKey
private typealias CallKey = CustomToolChatContract.CallKey
private typealias PayloadKey = CustomToolChatContract.PayloadKey

struct CustomToolChatStreamState {
    struct Key: Hashable {
        let choice: Int
        let index: Int
    }
    struct Call {
        var value: JSONValue
        var completed = false
    }
    var calls: [Key: Call] = [:]
    private var retainedBytes = 0

    mutating func consume(_ value: JSONValue, projection: CustomToolProjection, maximumBytes: Int) throws -> JSONValue {
        guard var root = value.object, let choices = root[CompletionKey.choices.rawValue]?.array else { return value }
        root[CompletionKey.choices.rawValue] = .array(
            try choices.map { choice in
                guard var fields = choice.object, let index = fields[ChoiceKey.index.rawValue]?.integer, index >= 0
                else {
                    throw CustomToolProjection.Error.invalidResponse
                }
                var delta = fields[ChoiceKey.delta.rawValue]?.object ?? [:]
                if let rawCalls = delta[MessageKey.toolCalls.rawValue]?.array {
                    var kept: [JSONValue] = []
                    for call in rawCalls
                    where try !retain(call, choice: index, projection: projection, maximumBytes: maximumBytes) {
                        kept.append(call)
                    }
                    if kept.isEmpty {
                        delta.removeValue(forKey: MessageKey.toolCalls.rawValue)
                    } else {
                        delta[MessageKey.toolCalls.rawValue] = .array(kept)
                    }
                }
                if let reason = fields[ChoiceKey.finishReason.rawValue]?.string {
                    let pending = calls.keys.filter { $0.choice == index && calls[$0]?.completed == false }.sorted {
                        $0.index < $1.index
                    }
                    guard
                        pending.isEmpty
                            || [OpenAIChatFinishReason.toolCalls.rawValue, OpenAIChatFinishReason.stop.rawValue]
                                .contains(reason)
                    else {
                        throw CustomToolProjection.Error.invalidResponse
                    }
                    var completed = delta[MessageKey.toolCalls.rawValue]?.array ?? []
                    for key in pending {
                        guard var call = calls[key], let id = call.value.object?[CallKey.id.rawValue]?.string,
                            !id.isEmpty,
                            let function = call.value.object?[CallKey.function.rawValue], projection.declares(function)
                        else { throw CustomToolProjection.Error.invalidResponse }
                        completed.append(try projection.restoreChatCall(call.value))
                        call.completed = true
                        calls[key] = call
                    }
                    if !completed.isEmpty { delta[MessageKey.toolCalls.rawValue] = .array(completed) }
                }
                if fields[ChoiceKey.delta.rawValue] != nil || !delta.isEmpty {
                    fields[ChoiceKey.delta.rawValue] = .object(delta)
                }
                return .object(fields)
            })
        return .object(root)
    }

    private mutating func retain(
        _ value: JSONValue, choice: Int, projection: CustomToolProjection, maximumBytes: Int
    ) throws -> Bool {
        guard let index = value.object?[CallKey.index.rawValue]?.integer, index >= 0 else {
            throw CustomToolProjection.Error.invalidResponse
        }
        let key = Key(choice: choice, index: index)
        if let previous = calls[key] {
            guard !previous.completed else { throw CustomToolProjection.Error.invalidResponse }
            try charge(try value.serializedData().count, maximumBytes: maximumBytes)
            calls[key] = Call(value: try merge(previous.value, value, projection: projection))
            return true
        }
        guard var fields = value.object,
            fields[CallKey.type.rawValue] == nil || fields[CallKey.type.rawValue] == .null
                || fields[CallKey.type.rawValue] == .string(OpenAIChatFunctionCallType.function.rawValue)
        else { return false }
        let name = fields[CallKey.function.rawValue]?.object?[PayloadKey.name.rawValue]?.string ?? ""
        guard projection.allowed.contains(where: { $0.name.starts(with: name.utf8) }) else { return false }
        guard calls.count < CustomToolStreamProjection.maximumCalls else {
            throw CustomToolProjection.Error.limitExceeded
        }
        try charge(try value.serializedData().count, maximumBytes: maximumBytes)
        fields[CallKey.type.rawValue] = .string(OpenAIChatFunctionCallType.function.rawValue)
        if fields[CallKey.id.rawValue] == .null { fields.removeValue(forKey: CallKey.id.rawValue) }
        if fields[CallKey.function.rawValue] == nil || fields[CallKey.function.rawValue] == .null {
            fields[CallKey.function.rawValue] = .object([:])
        }
        calls[key] = Call(value: .object(fields))
        return true
    }

    private func merge(_ previous: JSONValue, _ next: JSONValue, projection: CustomToolProjection) throws -> JSONValue {
        guard var root = previous.object, let update = next.object,
            var function = root[CallKey.function.rawValue]?.object
        else {
            throw CustomToolProjection.Error.invalidResponse
        }
        for (key, value) in update where key != CallKey.function.rawValue && value != .null {
            guard root[key] == nil || root[key] == value else { throw CustomToolProjection.Error.invalidResponse }
            root[key] = value
        }
        for (key, value) in update[CallKey.function.rawValue]?.object ?? [:] where value != .null {
            if key == PayloadKey.arguments.rawValue {
                guard let text = value.string else { throw CustomToolProjection.Error.invalidResponse }
                function[key] = .string((function[key]?.string ?? "") + text)
            } else if key == PayloadKey.name.rawValue {
                guard let text = value.string else { throw CustomToolProjection.Error.invalidResponse }
                let old = function[key]?.string ?? ""
                if value != function[key] || !projection.declares(.object(function)) {
                    function[key] = .string(old + text)
                }
            } else {
                guard function[key] == nil || function[key] == value else {
                    throw CustomToolProjection.Error.invalidResponse
                }
                function[key] = value
            }
        }
        root[CallKey.function.rawValue] = .object(function)
        return .object(root)
    }

    private mutating func charge(_ bytes: Int, maximumBytes: Int) throws {
        guard bytes <= maximumBytes - retainedBytes else { throw CustomToolProjection.Error.limitExceeded }
        retainedBytes += bytes
    }
}
