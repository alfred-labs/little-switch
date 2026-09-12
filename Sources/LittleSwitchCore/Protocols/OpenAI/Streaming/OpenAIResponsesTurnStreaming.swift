import Foundation
import LittleSwitchTransport

package struct OpenAIResponsesTurnAccumulator: Sendable {
    private enum Phase: Sendable {
        case awaitingResponse
        case streaming
        case terminal
        case finished
    }

    private struct ContentPart: Sendable {
        let type: String
        var completedText: String?
    }

    private struct ContentReference: Sendable {
        let outputIndex: Int
        let contentIndex: Int
        let itemID: String
    }

    private struct OutputItem: Sendable {
        let id: String
        let type: String
        let name: String?
        let namespace: String?
        let publicName: String
        let callID: String?
        var completedArguments: String?
        var contentParts: [Int: ContentPart] = [:]
    }

    private let maximumTurnBytes: Int
    private let toolBindings: [String: ResponsesToolNamespaces.Binding]
    private let resolver: ProviderToolNamespaceResolver
    private let privateToolName: String?
    private var consumedBytes = 0
    private var phase = Phase.awaitingResponse
    private var responseID: String?
    private var outputItems: [Int: OutputItem] = [:]
    private var completedOutput = ResponsesCompletedTurnOutput()
    private var terminalStatus: ResponsesStreamTerminal?
    private var terminalResponseJSON: Data?

    package init(
        maximumTurnBytes: Int,
        toolBindings: [String: ResponsesToolNamespaces.Binding] = [:],
        declaredToolBindings: [String: ResponsesToolNamespaces.Binding] = [:],
        toolNameCatalog: ProviderToolNameCatalog = .init(),
        privateToolName: String? = "web_search"
    ) {
        self.maximumTurnBytes = max(0, maximumTurnBytes)
        self.toolBindings = toolBindings
        self.resolver = ProviderToolNamespaceResolver(
            declaredBindings: declaredToolBindings,
            nameCatalog: toolNameCatalog
        )
        self.privateToolName = privateToolName
    }

    package mutating func consume(
        _ frame: ServerSentEventFrame
    ) throws -> [ResponsesProviderStreamEvent] {
        guard !frame.terminal else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        try charge(frame.data.count)
        let payload = try responsesStreamObject(frame.data)
        guard let type = nonemptyResponsesString(payload["type"]) else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }

        switch type {
        case "response.created":
            return [try consumeResponseCreated(payload)]
        case "response.output_item.added":
            return [try consumeOutputItemAdded(payload)]
        case "response.output_item.done":
            return [try consumeOutputItemDone(payload)]
        case "response.content_part.added":
            return [try consumeContentPartAdded(payload)]
        case "response.output_text.delta":
            return [try consumeOutputTextDelta(payload)]
        case "response.output_text.done":
            return [try consumeOutputTextDone(payload)]
        case "response.function_call_arguments.delta":
            return [try consumeFunctionArgumentsDelta(payload)]
        case "response.function_call_arguments.done":
            return [try consumeFunctionArgumentsDone(payload)]
        case "response.custom_tool_call_input.delta":
            return [try consumeFunctionArgumentsDelta(payload, kind: .custom)]
        case "response.custom_tool_call_input.done":
            return [try consumeFunctionArgumentsDone(payload, kind: .custom)]
        case "response.completed":
            return [try consumeTerminal(payload, status: .completed)]
        case "response.incomplete":
            return [try consumeTerminal(payload, status: .incomplete)]
        case "response.failed":
            return [try consumeTerminal(payload, status: .failed)]
        case "error":
            guard phase == .streaming else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            return []
        case "response.content_part.done":
            try consumeContentPartDone(payload)
            return [.passthrough(type: type, payloadJSON: try responsesStreamData(payload))]
        default:
            guard phase == .streaming else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            try validatePassthroughReference(payload)
            return [.passthrough(type: type, payloadJSON: try responsesStreamData(payload))]
        }
    }

    package mutating func finish() throws -> ResponsesModelTurn {
        // A body that ends while the turn is still open is a connection
        // dropped mid-stream: the provider never delivered a terminal event.
        guard phase == .terminal else {
            if phase == .awaitingResponse || phase == .streaming {
                throw OpenAIResponsesWebSearch.Error.streamEndedBeforeTerminal
            }
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        guard terminalStatus != .failed,
            outputItems.isEmpty,
            let terminalResponseJSON
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let turn = try OpenAIResponsesWebSearch.parseModelTurn(terminalResponseJSON, privateToolName: privateToolName)
        phase = .finished
        return turn
    }
}

extension OpenAIResponsesTurnAccumulator {
    private mutating func consumeResponseCreated(
        _ payload: [String: Any]
    ) throws -> ResponsesProviderStreamEvent {
        guard phase == .awaitingResponse,
            let response = payload["response"] as? [String: Any],
            let id = nonemptyResponsesString(response["id"]),
            response["object"] as? String == "response",
            response["output"] is [Any]
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        if let status = response["status"] as? String {
            guard ["queued", "in_progress"].contains(status) else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
        }
        responseID = id
        phase = .streaming
        return .responseStarted(responseJSON: try responsesStreamData(response))
    }

    private mutating func consumeOutputItemAdded(
        _ payload: [String: Any]
    ) throws -> ResponsesProviderStreamEvent {
        guard phase == .streaming,
            let outputIndex = nonnegativeResponsesIndex(payload["output_index"]),
            outputItems[outputIndex] == nil,
            let item = payload["item"] as? [String: Any],
            let id = nonemptyResponsesString(item["id"]),
            let type = nonemptyResponsesString(item["type"])
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }

        let function = try responsesFunctionMetadata(
            item, required: ["function_call", "custom_tool_call"].contains(type))
        if type == "message", let content = item["content"], !(content is [Any]) {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let binding = function.flatMap { bindingFor(name: $0.name, namespace: $0.namespace) }
        outputItems[outputIndex] = OutputItem(
            id: id,
            type: type,
            name: function?.name,
            namespace: function?.namespace,
            publicName: binding?.name ?? function?.name ?? id,
            callID: function?.callID
        )
        return .outputItemAdded(
            outputIndex: outputIndex,
            itemJSON: try responsesStreamData(restoredResponsesToolItem(item, binding: binding))
        )
    }

    private mutating func consumeOutputItemDone(
        _ payload: [String: Any]
    ) throws -> ResponsesProviderStreamEvent {
        guard phase == .streaming,
            let outputIndex = nonnegativeResponsesIndex(payload["output_index"]),
            let state = outputItems[outputIndex],
            state.contentParts.isEmpty,
            let item = payload["item"] as? [String: Any],
            nonemptyResponsesString(item["id"]) == state.id,
            nonemptyResponsesString(item["type"]) == state.type
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }

        if ["function_call", "custom_tool_call"].contains(state.type) {
            let metadata = try responsesFunctionMetadata(item, required: true)
            guard metadata?.name == state.name,
                metadata?.namespace == state.namespace,
                metadata?.callID == state.callID,
                let arguments = item[state.type == "custom_tool_call" ? "input" : "arguments"] as? String,
                state.completedArguments == arguments
            else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
        }
        try completedOutput.record(item, at: outputIndex)
        outputItems.removeValue(forKey: outputIndex)
        return .outputItemDone(
            outputIndex: outputIndex,
            itemJSON: try responsesStreamData(
                restoredResponsesToolItem(
                    item,
                    binding: state.name.flatMap { bindingFor(name: $0, namespace: state.namespace) }
                )
            )
        )
    }

    private mutating func consumeContentPartAdded(
        _ payload: [String: Any]
    ) throws -> ResponsesProviderStreamEvent {
        guard phase == .streaming,
            let outputIndex = nonnegativeResponsesIndex(payload["output_index"]),
            let contentIndex = nonnegativeResponsesIndex(payload["content_index"]),
            let itemID = nonemptyResponsesString(payload["item_id"]),
            var item = outputItems[outputIndex],
            item.id == itemID,
            item.contentParts[contentIndex] == nil,
            let part = payload["part"] as? [String: Any],
            let type = nonemptyResponsesString(part["type"])
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }

        if type == "output_text" {
            guard part["text"] is String else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
        }
        item.contentParts[contentIndex] = ContentPart(type: type)
        outputItems[outputIndex] = item
        return .contentPartAdded(
            outputIndex: outputIndex,
            contentIndex: contentIndex,
            itemID: itemID,
            partJSON: try responsesStreamData(part)
        )
    }

    private mutating func consumeOutputTextDelta(
        _ payload: [String: Any]
    ) throws -> ResponsesProviderStreamEvent {
        guard phase == .streaming else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let reference = try contentReference(payload)
        guard let delta = payload["delta"] as? String,
            let item = outputItems[reference.outputIndex],
            let part = item.contentParts[reference.contentIndex],
            part.type == "output_text",
            part.completedText == nil
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        return .outputTextDelta(
            outputIndex: reference.outputIndex,
            contentIndex: reference.contentIndex,
            itemID: reference.itemID,
            delta: delta
        )
    }

    private mutating func consumeOutputTextDone(
        _ payload: [String: Any]
    ) throws -> ResponsesProviderStreamEvent {
        guard phase == .streaming else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let reference = try contentReference(payload)
        guard let text = payload["text"] as? String,
            var item = outputItems[reference.outputIndex],
            var part = item.contentParts[reference.contentIndex],
            part.type == "output_text",
            part.completedText == nil
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        part.completedText = text
        item.contentParts[reference.contentIndex] = part
        outputItems[reference.outputIndex] = item
        return .outputTextDone(
            outputIndex: reference.outputIndex,
            contentIndex: reference.contentIndex,
            itemID: reference.itemID,
            text: text
        )
    }

    private mutating func consumeFunctionArgumentsDelta(
        _ payload: [String: Any], kind: ProviderToolContractCatalog.Kind = .function
    ) throws -> ResponsesProviderStreamEvent {
        guard phase == .streaming,
            let outputIndex = nonnegativeResponsesIndex(payload["output_index"]),
            let itemID = nonemptyResponsesString(payload["item_id"]),
            let delta = payload["delta"] as? String,
            let item = outputItems[outputIndex],
            item.id == itemID,
            item.type == kind.responseType,
            let callID = item.callID,
            let name = item.name,
            item.completedArguments == nil
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        try validateOptionalFunctionMetadata(payload, callID: callID, name: name)
        if kind == .custom {
            return .customInputDelta(
                outputIndex: outputIndex, itemID: itemID, callID: callID, name: item.publicName, delta: delta)
        }
        return .functionArgumentsDelta(
            outputIndex: outputIndex,
            itemID: itemID,
            callID: callID,
            name: item.publicName,
            delta: delta
        )
    }

    private mutating func consumeFunctionArgumentsDone(
        _ payload: [String: Any], kind: ProviderToolContractCatalog.Kind = .function
    ) throws -> ResponsesProviderStreamEvent {
        guard phase == .streaming,
            let outputIndex = nonnegativeResponsesIndex(payload["output_index"]),
            let itemID = nonemptyResponsesString(payload["item_id"]),
            let arguments = payload[kind.inputKey] as? String,
            var item = outputItems[outputIndex],
            item.id == itemID,
            item.type == kind.responseType,
            let callID = item.callID,
            let name = item.name,
            item.completedArguments == nil
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        try validateOptionalFunctionMetadata(payload, callID: callID, name: name)
        item.completedArguments = arguments
        outputItems[outputIndex] = item
        if kind == .custom {
            return .customInputDone(
                outputIndex: outputIndex, itemID: itemID, callID: callID, name: item.publicName, input: arguments)
        }
        return .functionArgumentsDone(
            outputIndex: outputIndex,
            itemID: itemID,
            callID: callID,
            name: item.publicName,
            arguments: arguments
        )
    }

    private mutating func consumeContentPartDone(_ payload: [String: Any]) throws {
        guard phase == .streaming else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let reference = try contentReference(payload)
        guard var item = outputItems[reference.outputIndex],
            let partState = item.contentParts[reference.contentIndex],
            let part = payload["part"] as? [String: Any],
            nonemptyResponsesString(part["type"]) == partState.type
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        if partState.type == "output_text" {
            guard let text = part["text"] as? String,
                partState.completedText == text
            else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
        }
        item.contentParts.removeValue(forKey: reference.contentIndex)
        outputItems[reference.outputIndex] = item
    }

    private mutating func consumeTerminal(
        _ payload: [String: Any],
        status: ResponsesStreamTerminal
    ) throws -> ResponsesProviderStreamEvent {
        guard phase == .streaming,
            outputItems.isEmpty,
            let response = payload["response"] as? [String: Any],
            nonemptyResponsesString(response["id"]) == responseID,
            response["object"] as? String == "response",
            response["status"] as? String == status.rawValue
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        if status == .failed {
            guard validResponsesFailedResponse(response, expectedID: responseID) else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
        } else {
            guard response["output"] is [Any],
                response["usage"] is [String: Any]
            else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
        }
        let data = try responsesStreamData(response)
        terminalStatus = status
        terminalResponseJSON =
            status == .failed ? nil : try completedOutput.restoringEmptyOutput(in: response, originalJSON: data)
        phase = .terminal
        return .terminal(status: status, responseJSON: data)
    }

    private func contentReference(
        _ payload: [String: Any]
    ) throws -> ContentReference {
        guard let outputIndex = nonnegativeResponsesIndex(payload["output_index"]),
            let contentIndex = nonnegativeResponsesIndex(payload["content_index"]),
            let itemID = nonemptyResponsesString(payload["item_id"]),
            let item = outputItems[outputIndex],
            item.id == itemID,
            item.contentParts[contentIndex] != nil
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        return ContentReference(
            outputIndex: outputIndex,
            contentIndex: contentIndex,
            itemID: itemID
        )
    }

    private func validatePassthroughReference(_ payload: [String: Any]) throws {
        guard let outputIndexValue = payload["output_index"] else {
            return
        }
        guard let outputIndex = nonnegativeResponsesIndex(outputIndexValue),
            let item = outputItems[outputIndex]
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        if let itemID = payload["item_id"] {
            guard nonemptyResponsesString(itemID) == item.id else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
        }
        if let contentIndexValue = payload["content_index"] {
            guard let contentIndex = nonnegativeResponsesIndex(contentIndexValue) else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            // Reasoning items stream their text without declaring content parts.
            guard item.type == "reasoning" || item.contentParts[contentIndex] != nil else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
        }
    }

    private mutating func charge(_ byteCount: Int) throws {
        guard consumedBytes <= maximumTurnBytes,
            byteCount <= maximumTurnBytes - consumedBytes
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        consumedBytes += byteCount
    }

    /// The binding for an emitted call name: the exact flattened wire name
    /// first, then a near-miss resolved among the request's declared children.
    /// A supplied namespace (a backend that natively restores the pair) is
    /// never fuzzed — only the exact pair resolves.
    private func bindingFor(
        name: String,
        namespace: String?
    ) -> ResponsesToolNamespaces.Binding? {
        resolver.restoredBinding(for: name, namespace: namespace, bindings: toolBindings)
    }

}
