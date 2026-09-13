import Foundation
import LittleSwitchTransport
import LittleSwitchWire

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
        let event = try responsesWireDecode(OpenAIResponseStreamEvent.self, from: frame.data)
        switch event {
        case .responseCreated(let value):
            return [try consumeResponseCreated(value)]
        case .responseOutputItemAdded(let value):
            return [try consumeOutputItemAdded(value)]
        case .responseOutputItemDone(let value):
            return [try consumeOutputItemDone(value)]
        case .responseContentPartAdded(let value):
            return [try consumeContentPartAdded(value)]
        case .responseOutputTextDelta(let value):
            return [try consumeOutputTextDelta(value)]
        case .responseOutputTextDone(let value):
            return [try consumeOutputTextDone(value)]
        case .responseFunctionCallArgumentsDelta(let value):
            return [try consumeFunctionArgumentsDelta(value)]
        case .responseFunctionCallArgumentsDone(let value):
            return [try consumeFunctionArgumentsDone(value)]
        case .responseCustomToolCallInputDelta(let value):
            return [try consumeFunctionArgumentsDelta(value, kind: .custom)]
        case .responseCustomToolCallInputDone(let value):
            return [try consumeFunctionArgumentsDone(value, kind: .custom)]
        case .responseCompleted(let value):
            return [try consumeTerminal(value.response, status: .completed)]
        case .responseIncomplete(let value):
            return [try consumeTerminal(value.response, status: .incomplete)]
        case .responseFailed(let value):
            return [try consumeTerminal(value.response, status: .failed)]
        case .error:
            guard phase == .streaming else { throw OpenAIResponsesWebSearch.Error.invalidResponse }
            return []
        case .responseContentPartDone(let value):
            try consumeContentPartDone(value)
            return [.passthrough(type: value.type.rawValue, payloadJSON: frame.data)]
        default:
            guard phase == .streaming else { throw OpenAIResponsesWebSearch.Error.invalidResponse }
            // Future events have no selected SDK record. Their existing Core
            // reference policy reads only correlation fields from an exact view.
            let payload = try responsesStreamObject(frame.data)
            guard let type = nonemptyResponsesString(payload["type"]) else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            try validatePassthroughReference(payload)
            return [.passthrough(type: type, payloadJSON: frame.data)]
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
        _ event: OpenAIResponsesCreatedEvent
    ) throws -> ResponsesProviderStreamEvent {
        guard phase == .awaitingResponse, let json = event.response else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let response = try responsesWireDecode(OpenAIResponsesResponse.self, json: json)
        guard !response.id.isEmpty, response.object == .response, response.output != nil,
            response.status == nil || response.status == .queued || response.status == .inProgress
        else { throw OpenAIResponsesWebSearch.Error.invalidResponse }
        responseID = response.id
        phase = .streaming
        return .responseStarted(responseJSON: try json.serializedData())
    }

    private mutating func consumeOutputItemAdded(
        _ event: OpenAIResponsesOutputItemAddedEvent
    ) throws -> ResponsesProviderStreamEvent {
        let outputIndex = try responsesWireIndex(event.outputIndex)
        guard phase == .streaming, outputItems[outputIndex] == nil, let json = event.item else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let item = try responsesWireDecode(OpenAIResponsesOutputItem.self, json: json)
        let metadata = try ResponsesStreamWireMetadata(item)
        let function = metadata.function
        let binding = function.flatMap { bindingFor(name: $0.name, namespace: $0.namespace) }
        outputItems[outputIndex] = OutputItem(
            id: metadata.id,
            type: metadata.type,
            name: function?.name,
            namespace: function?.namespace,
            publicName: binding?.name ?? function?.name ?? metadata.id,
            callID: function?.callID
        )
        return .outputItemAdded(
            outputIndex: outputIndex,
            itemJSON: try WireCodec.encode(restoredResponsesToolItem(item, binding: binding))
        )
    }

    private mutating func consumeOutputItemDone(
        _ event: OpenAIResponsesOutputItemDoneEvent
    ) throws -> ResponsesProviderStreamEvent {
        let outputIndex = try responsesWireIndex(event.outputIndex)
        guard phase == .streaming, let state = outputItems[outputIndex],
            state.contentParts.isEmpty, let json = event.item
        else { throw OpenAIResponsesWebSearch.Error.invalidResponse }
        let item = try responsesWireDecode(OpenAIResponsesOutputItem.self, json: json)
        let metadata = try ResponsesStreamWireMetadata(item)
        guard metadata.id == state.id, metadata.type == state.type else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        if let function = metadata.function {
            guard function.name == state.name, function.namespace == state.namespace,
                function.callID == state.callID, metadata.toolInput == state.completedArguments
            else { throw OpenAIResponsesWebSearch.Error.invalidResponse }
        }
        completedOutput.record(json, at: outputIndex)
        outputItems.removeValue(forKey: outputIndex)
        let binding = state.name.flatMap { bindingFor(name: $0, namespace: state.namespace) }
        return .outputItemDone(
            outputIndex: outputIndex,
            itemJSON: try WireCodec.encode(restoredResponsesToolItem(item, binding: binding))
        )
    }

    private mutating func consumeContentPartAdded(
        _ event: OpenAIContentPartAdded
    ) throws -> ResponsesProviderStreamEvent {
        let outputIndex = try responsesWireIndex(event.outputIndex)
        let contentIndex = try responsesWireIndex(event.contentIndex)
        guard phase == .streaming, !event.itemId.isEmpty,
            var item = outputItems[outputIndex], item.id == event.itemId,
            item.contentParts[contentIndex] == nil, let json = event.part
        else { throw OpenAIResponsesWebSearch.Error.invalidResponse }
        let part = try responsesWireDecode(OpenAIResponsesContentPart.self, json: json)
        guard !part.streamType.isEmpty else { throw OpenAIResponsesWebSearch.Error.invalidResponse }
        item.contentParts[contentIndex] = ContentPart(type: part.streamType)
        outputItems[outputIndex] = item
        return .contentPartAdded(
            outputIndex: outputIndex,
            contentIndex: contentIndex,
            itemID: event.itemId,
            partJSON: try json.serializedData()
        )
    }

    private mutating func consumeOutputTextDelta(
        _ event: OpenAIResponsesTextDeltaEvent
    ) throws -> ResponsesProviderStreamEvent {
        guard phase == .streaming else { throw OpenAIResponsesWebSearch.Error.invalidResponse }
        let reference = try contentReference(
            outputIndex: event.outputIndex, contentIndex: event.contentIndex, itemID: event.itemId)
        guard let item = outputItems[reference.outputIndex],
            let part = item.contentParts[reference.contentIndex],
            part.type == OpenAIResponsesOutputTextType.outputText.rawValue, part.completedText == nil
        else { throw OpenAIResponsesWebSearch.Error.invalidResponse }
        return .outputTextDelta(
            outputIndex: reference.outputIndex,
            contentIndex: reference.contentIndex,
            itemID: reference.itemID,
            delta: event.delta
        )
    }

    private mutating func consumeOutputTextDone(
        _ event: OpenAIResponsesTextDoneEvent
    ) throws -> ResponsesProviderStreamEvent {
        guard phase == .streaming else { throw OpenAIResponsesWebSearch.Error.invalidResponse }
        let reference = try contentReference(
            outputIndex: event.outputIndex, contentIndex: event.contentIndex, itemID: event.itemId)
        guard var item = outputItems[reference.outputIndex],
            var part = item.contentParts[reference.contentIndex],
            part.type == OpenAIResponsesOutputTextType.outputText.rawValue, part.completedText == nil
        else { throw OpenAIResponsesWebSearch.Error.invalidResponse }
        part.completedText = event.text
        item.contentParts[reference.contentIndex] = part
        outputItems[reference.outputIndex] = item
        return .outputTextDone(
            outputIndex: reference.outputIndex,
            contentIndex: reference.contentIndex,
            itemID: reference.itemID,
            text: event.text
        )
    }

    private mutating func consumeFunctionArgumentsDelta(
        _ event: some ResponsesToolInputWireEvent, kind: ProviderToolContractCatalog.Kind = .function
    ) throws -> ResponsesProviderStreamEvent {
        let outputIndex = try responsesWireIndex(event.outputIndex)
        guard phase == .streaming, !event.itemId.isEmpty,
            let item = outputItems[outputIndex], item.id == event.itemId,
            item.type == kind.responseType, let callID = item.callID,
            let name = item.name, item.completedArguments == nil
        else { throw OpenAIResponsesWebSearch.Error.invalidResponse }
        try validateToolInputMetadata(event, callID: callID, name: name)
        if kind == .custom {
            return .customInputDelta(
                outputIndex: outputIndex,
                itemID: event.itemId,
                callID: callID,
                name: item.publicName,
                delta: event.inputText)
        }
        return .functionArgumentsDelta(
            outputIndex: outputIndex,
            itemID: event.itemId,
            callID: callID,
            name: item.publicName,
            delta: event.inputText
        )
    }

    private mutating func consumeFunctionArgumentsDone(
        _ event: some ResponsesToolInputWireEvent, kind: ProviderToolContractCatalog.Kind = .function
    ) throws -> ResponsesProviderStreamEvent {
        let outputIndex = try responsesWireIndex(event.outputIndex)
        guard phase == .streaming, !event.itemId.isEmpty,
            var item = outputItems[outputIndex], item.id == event.itemId,
            item.type == kind.responseType, let callID = item.callID,
            let name = item.name, item.completedArguments == nil
        else { throw OpenAIResponsesWebSearch.Error.invalidResponse }
        try validateToolInputMetadata(event, callID: callID, name: name)
        item.completedArguments = event.inputText
        outputItems[outputIndex] = item
        if kind == .custom {
            return .customInputDone(
                outputIndex: outputIndex,
                itemID: event.itemId,
                callID: callID,
                name: item.publicName,
                input: event.inputText)
        }
        return .functionArgumentsDone(
            outputIndex: outputIndex,
            itemID: event.itemId,
            callID: callID,
            name: item.publicName,
            arguments: event.inputText
        )
    }

    private func validateToolInputMetadata(
        _ event: some ResponsesToolInputWireEvent,
        callID: String,
        name: String
    ) throws {
        guard event.callId.value == nil || event.callId.value == callID,
            event.name.value == nil || event.name.value == name
        else { throw OpenAIResponsesWebSearch.Error.invalidResponse }
    }

    private mutating func consumeContentPartDone(_ event: OpenAIContentPartDone) throws {
        guard phase == .streaming else { throw OpenAIResponsesWebSearch.Error.invalidResponse }
        let reference = try contentReference(
            outputIndex: event.outputIndex, contentIndex: event.contentIndex, itemID: event.itemId)
        guard var item = outputItems[reference.outputIndex],
            let partState = item.contentParts[reference.contentIndex], let json = event.part
        else { throw OpenAIResponsesWebSearch.Error.invalidResponse }
        let part = try responsesWireDecode(OpenAIResponsesContentPart.self, json: json)
        guard part.streamType == partState.type else { throw OpenAIResponsesWebSearch.Error.invalidResponse }
        if let text = part.streamText, partState.completedText != text {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        item.contentParts.removeValue(forKey: reference.contentIndex)
        outputItems[reference.outputIndex] = item
    }

    private mutating func consumeTerminal(
        _ json: JSONValue?, status: ResponsesStreamTerminal
    ) throws -> ResponsesProviderStreamEvent {
        guard phase == .streaming, outputItems.isEmpty, let json else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let response = try responsesWireDecode(OpenAIResponsesResponse.self, json: json)
        guard !response.id.isEmpty, response.id == responseID, response.object == .response,
            response.status?.rawValue == status.rawValue
        else { throw OpenAIResponsesWebSearch.Error.invalidResponse }
        if status == .failed {
            guard response.error.value.map({ !$0.code.rawValue.isEmpty }) ?? true else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
        } else if response.output == nil || response.usage.value == nil {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let data = try json.serializedData()
        terminalStatus = status
        terminalResponseJSON =
            status == .failed ? nil : try completedOutput.restoringEmptyOutput(in: response, originalJSON: data)
        phase = .terminal
        return .terminal(status: status, responseJSON: data)
    }

    private func contentReference(
        outputIndex: JSONNumber, contentIndex: JSONNumber, itemID: String
    ) throws -> ContentReference {
        let outputIndex = try responsesWireIndex(outputIndex)
        let contentIndex = try responsesWireIndex(contentIndex)
        guard !itemID.isEmpty, let item = outputItems[outputIndex],
            item.id == itemID, item.contentParts[contentIndex] != nil
        else { throw OpenAIResponsesWebSearch.Error.invalidResponse }
        return ContentReference(outputIndex: outputIndex, contentIndex: contentIndex, itemID: itemID)
    }

    private func validatePassthroughReference(_ payload: [String: Any]) throws {
        guard let outputIndexValue = payload["output_index"] else { return }
        guard let outputIndex = nonnegativeResponsesIndex(outputIndexValue), let item = outputItems[outputIndex] else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        if let itemID = payload["item_id"], nonemptyResponsesString(itemID) != item.id {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        if let contentIndexValue = payload["content_index"] {
            guard let contentIndex = nonnegativeResponsesIndex(contentIndexValue),
                item.type == OpenAIResponsesReasoningType.reasoning.rawValue || item.contentParts[contentIndex] != nil
            else { throw OpenAIResponsesWebSearch.Error.invalidResponse }
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
