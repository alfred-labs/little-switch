import Foundation
import LittleSwitchWire

private struct ChatToolInputDelta {
    let name: String?
    let namespace: String?
    let input: String?
}

/// Retains only an unresolved identity and its pending input; settled calls stream immediately.
struct ChatCompletionToolStream {
    let prepared: PreparedResponsesChatCompletionsRequest
    let resolver: ProviderToolNamespaceResolver
    let metadata: ChatCompletionStreamMetadata

    func consume(
        _ rawCall: OpenAIChatToolDelta,
        state: inout ChatCompletionChoiceState,
        fragments: inout ChatCompletionFragmentBuffer
    ) throws -> [ResponsesProviderStreamEvent] {
        let index = try chatWireIndex(rawCall.index)
        let previous = state.toolCalls[index]
        let kind: ProviderToolContractCatalog.Kind
        if let parsed = rawCall.type.value {
            guard previous == nil || previous?.kind == parsed
            else { throw invalid }
            kind = parsed
        } else {
            guard let previous else { throw invalid }
            kind = previous.kind
        }
        let input = inputDelta(rawCall, kind: kind)
        var call: ChatCompletionToolCallState
        if let previous {
            call = previous
            if let id = rawCall.id.value, id != call.callID { throw invalid }
        } else {
            guard let callID = rawCall.id.value, !callID.isEmpty,
                let name = input?.name, !name.isEmpty
            else { throw invalid }
            let offset = state.toolOutputOffset ?? (state.leadingOutputCount + (state.message == nil ? 0 : 1))
            let outputIndex = offset.addingReportingOverflow(index)
            guard !outputIndex.overflow else { throw invalid }
            state.toolOutputOffset = offset
            call = ChatCompletionToolCallState(
                itemID: "\(kind.itemIDPrefix)_\(metadata.responseID)_\(index)",
                callID: callID,
                kind: kind,
                name: name,
                outputIndex: outputIndex.partialValue,
                completedArguments: "")
        }
        if let namespace = input?.namespace {
            guard !namespace.isEmpty,
                (!call.published && call.namespace == nil) || call.namespace == namespace
            else {
                throw invalid
            }
            call.namespace = namespace
        }
        // Qualify the identity before deciding whether a repeated name is
        // complete: a pending bare name can acquire its namespace later.
        if previous != nil, let name = input?.name {
            if call.published {
                guard name == call.name else { throw invalid }
            } else if name != call.name || !isComplete(call) {
                call.name += name
            }
        }
        if let fragment = input?.input {
            if !fragment.isEmpty {
                fragments.appendArguments(
                    fragment,
                    choiceIndex: state.index,
                    toolIndex: index)
                call.pendingArguments.append(fragment)
            }
        }
        let events = try publish(
            &call,
            completedName: false)
        state.toolCalls[index] = call
        return events
    }

    private func inputDelta(_ call: OpenAIChatToolDelta, kind: OpenAIChatToolKind) -> ChatToolInputDelta? {
        switch kind {
        case .function:
            call.function.map {
                ChatToolInputDelta(name: $0.name.value, namespace: $0.namespace.value, input: $0.arguments)
            }
        case .custom:
            call.custom.map { ChatToolInputDelta(name: $0.name.value, namespace: $0.namespace.value, input: $0.input) }
        }
    }

    func complete(
        _ state: inout ChatCompletionChoiceState,
        fragments: inout ChatCompletionFragmentBuffer
    ) throws -> [ResponsesProviderStreamEvent] {
        var events: [ResponsesProviderStreamEvent] = []
        for (index, value) in state.toolCalls.sorted(by: { $0.key < $1.key }) {
            var call = value
            events += try publish(
                &call,
                completedName: true)
            call.completedArguments = fragments.finalizeArguments(
                choiceIndex: state.index,
                toolIndex: index)
            let binding = try binding(for: call)
            let publicName = binding?.name ?? call.name
            if call.kind == .function {
                events.append(
                    .functionArgumentsDone(
                        outputIndex: call.outputIndex,
                        itemID: call.itemID,
                        callID: call.callID,
                        name: publicName,
                        arguments: call.completedArguments))
            } else {
                events.append(
                    .customInputDone(
                        outputIndex: call.outputIndex,
                        itemID: call.itemID,
                        callID: call.callID,
                        name: publicName,
                        input: call.completedArguments))
            }
            events.append(
                .outputItemDone(
                    outputIndex: call.outputIndex,
                    itemJSON: try item(
                        call,
                        binding: binding,
                        completed: true)))
            state.toolCalls[index] = call
        }
        return events
    }

    private func publish(
        _ call: inout ChatCompletionToolCallState,
        completedName: Bool
    ) throws -> [ResponsesProviderStreamEvent] {
        guard isComplete(call) else {
            guard !completedName else { throw invalid }
            return []
        }
        if !call.published, !completedName, hasLongerIdentity(call) { return [] }
        let binding = try binding(for: call)
        var events: [ResponsesProviderStreamEvent] = []
        if !call.published {
            events.append(
                .outputItemAdded(
                    outputIndex: call.outputIndex,
                    itemJSON: try item(
                        call,
                        binding: binding,
                        completed: false)))
            call.published = true
        }
        for fragment in call.pendingArguments {
            if call.kind == .function {
                events.append(
                    .functionArgumentsDelta(
                        outputIndex: call.outputIndex,
                        itemID: call.itemID,
                        callID: call.callID,
                        name: binding?.name ?? call.name,
                        delta: fragment))
            } else {
                events.append(
                    .customInputDelta(
                        outputIndex: call.outputIndex,
                        itemID: call.itemID,
                        callID: call.callID,
                        name: binding?.name ?? call.name,
                        delta: fragment))
            }
        }
        call.pendingArguments.removeAll(keepingCapacity: false)
        return events
    }

    private func hasLongerIdentity(_ call: ChatCompletionToolCallState) -> Bool {
        if let namespace = call.namespace {
            return prepared.declaredToolBindings.values.contains {
                $0.namespace == namespace && $0.name != call.name && $0.name.hasPrefix(call.name)
            }
        }
        return prepared.toolNameCatalog.declared.contains { $0 != call.name && $0.hasPrefix(call.name) }
    }

    private func isComplete(_ call: ChatCompletionToolCallState) -> Bool {
        let identity = ProviderToolContractCatalog.Identity(name: call.name, namespace: call.namespace, kind: call.kind)
        if prepared.allowedToolIdentities.contains(identity) { return true }
        guard let wireName = resolver.wireName(for: call.name, namespace: call.namespace) else { return false }
        return prepared.allowedToolIdentities.contains(.init(name: wireName, namespace: nil, kind: call.kind))
    }

    private func binding(for call: ChatCompletionToolCallState) throws -> ResponsesToolNamespaces.Binding? {
        try restoredChatToolBinding(
            name: call.name,
            namespace: call.namespace,
            bindings: prepared.toolBindings,
            resolver: resolver)
    }

    private func item(
        _ call: ChatCompletionToolCallState,
        binding: ResponsesToolNamespaces.Binding?,
        completed: Bool
    ) throws -> Data {
        if call.kind == .function {
            return try WireCodec.encode(
                chatFunctionItem(
                    itemID: call.itemID,
                    callID: call.callID,
                    name: call.name,
                    arguments: call.completedArguments,
                    status: completed ? .completed : .inProgress,
                    binding: binding))
        }
        return try WireCodec.encode(
            OpenAIResponsesCustomCall(
                callId: call.callID,
                id: call.itemID,
                input: completed ? call.completedArguments : "",
                name: binding?.name ?? call.name,
                namespace: binding.map { .value($0.namespace) } ?? .absent,
                status: .value(completed ? .completed : .inProgress),
                type: .customToolCall))
    }

    private var invalid: OpenAIResponsesChatCompletions.Error { .invalidResponse }
}
