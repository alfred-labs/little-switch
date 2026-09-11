import Foundation

extension ResponsesPublicStreamSession {
    package mutating func start(responseJSON: Data) throws -> [Data] {
        guard terminalState == .open,
            !started,
            !configuration.originalModel.isEmpty
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let providerResponse = try publicResponseObject(responseJSON)
        guard providerResponse["output"] is [Any] else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        var response = try OpenAIResponsesPublicSanitizer.responseShell(
            provider: providerResponse
        )
        guard let id = nonemptyResponsesString(response["id"]),
            let createdAt = nonnegativeResponsesIndex(response["created_at"])
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }

        try applyClientMetadata(to: &response)
        response["id"] = id
        response["created_at"] = createdAt
        response["completed_at"] = NSNull()
        response["error"] = NSNull()
        response["incomplete_details"] = NSNull()
        response["output"] = []
        response["status"] = "in_progress"
        response["usage"] = NSNull()

        let normalized = try responsesStreamData(response)
        firstResponseJSON = normalized
        publicResponseID = id
        publicCreatedAt = createdAt
        started = true
        providerTurnActive = true

        return [
            try frame("response.created", payload: ["response": response]),
            try frame("response.in_progress", payload: ["response": response]),
        ]
    }

    package mutating func consumePublic(
        _ event: ResponsesProviderStreamEvent
    ) throws -> [Data] {
        guard terminalState == .open,
            started,
            pendingSearch == nil
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }

        // Swift Format expands these bindings in the form SwiftLint rejects.
        // swiftlint:disable pattern_matching_keywords
        switch event {
        case .responseStarted(let responseJSON):
            return try beginProviderTurn(responseJSON)
        case .outputItemAdded(let outputIndex, let itemJSON):
            return try consumeOutputItemAdded(outputIndex: outputIndex, itemJSON: itemJSON)
        case .outputItemDone(let outputIndex, let itemJSON):
            return try consumeOutputItemDone(outputIndex: outputIndex, itemJSON: itemJSON)
        case .contentPartAdded(let outputIndex, let contentIndex, let itemID, let partJSON):
            return try consumeContentPartAdded(
                outputIndex: outputIndex,
                contentIndex: contentIndex,
                itemID: itemID,
                partJSON: partJSON
            )
        case .outputTextDelta(let outputIndex, let contentIndex, let itemID, let delta):
            return try consumeOutputTextDelta(
                outputIndex: outputIndex,
                contentIndex: contentIndex,
                itemID: itemID,
                delta: delta
            )
        case .outputTextDone(let outputIndex, let contentIndex, let itemID, let text):
            return try consumeOutputTextDone(
                outputIndex: outputIndex,
                contentIndex: contentIndex,
                itemID: itemID,
                text: text
            )
        case .functionArgumentsDelta(let outputIndex, let itemID, let callID, let name, let delta):
            return try consumeFunctionArgumentsDelta(
                outputIndex: outputIndex,
                itemID: itemID,
                callID: callID,
                name: name,
                delta: delta
            )
        case .functionArgumentsDone(let outputIndex, let itemID, let callID, let name, let arguments):
            return try consumeFunctionArgumentsDone(
                outputIndex: outputIndex,
                itemID: itemID,
                callID: callID,
                name: name,
                arguments: arguments
            )
        case .customInputDelta(let outputIndex, let itemID, let callID, let name, let delta):
            return try consumeCustomInput(
                .init(index: outputIndex, itemID: itemID, callID: callID, name: name), value: delta, completed: false)
        case .customInputDone(let outputIndex, let itemID, let callID, let name, let input):
            return try consumeCustomInput(
                .init(index: outputIndex, itemID: itemID, callID: callID, name: name), value: input, completed: true)
        case .passthrough(let type, let payloadJSON):
            return try consumePassthrough(type: type, payloadJSON: payloadJSON)
        case .terminal(let status, let responseJSON):
            return try consumeProviderTerminal(status: status, responseJSON: responseJSON)
        }
        // swiftlint:enable pattern_matching_keywords
    }

    package mutating func beginSearch(id: String, query: String) throws -> [Data] {
        guard terminalState == .open,
            started,
            !providerTurnActive,
            providerOutput.isEmpty,
            pendingSearch == nil,
            !id.isEmpty,
            !usedPublicItemIDs.contains(id)
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let outputIndex = try allocateOutputIndex()
        let search = PendingSearch(id: id, query: query, outputIndex: outputIndex)
        let item: [String: Any] = [
            "type": "web_search_call",
            "id": id,
            "status": "in_progress",
        ]
        let reference: [String: Any] = [
            "item_id": id,
            "output_index": outputIndex,
        ]
        usedPublicItemIDs.insert(id)
        pendingSearch = search
        return [
            try frame(
                "response.output_item.added",
                payload: ["output_index": outputIndex, "item": item]
            ),
            try frame("response.web_search_call.in_progress", payload: reference),
            try frame("response.web_search_call.searching", payload: reference),
        ]
    }

    package mutating func finishSearch(
        id: String,
        query: String,
        sources: [String] = [],
        failed: Bool = false
    ) throws -> [Data] {
        guard terminalState == .open,
            let pendingSearch,
            pendingSearch.id == id,
            pendingSearch.query == query
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let item = try OpenAIResponsesWebSearch.nativeSearchItem(
            id: id,
            query: query,
            sources: sources,
            failed: failed
        )
        let reference: [String: Any] = [
            "item_id": id,
            "output_index": pendingSearch.outputIndex,
        ]
        completedOutput[pendingSearch.outputIndex] = try responsesStreamData(item)
        self.pendingSearch = nil
        var frames: [Data] = []
        if !failed {
            frames.append(try frame("response.web_search_call.completed", payload: reference))
        }
        frames.append(
            try frame(
                "response.output_item.done",
                payload: ["output_index": pendingSearch.outputIndex, "item": item]
            )
        )
        return frames
    }

    package mutating func finish(
        responseJSON: Data,
        usage: ResponsesUsage
    ) throws -> [Data] {
        guard terminalState == .open,
            started,
            providerOutput.isEmpty,
            pendingSearch == nil,
            usage.inputTokens >= 0,
            usage.outputTokens >= 0
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let source = try publicResponseObject(responseJSON)
        guard let statusValue = source["status"] as? String,
            let status = ResponsesStreamTerminal(rawValue: statusValue)
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        if status == .failed {
            guard validResponsesFailedResponse(source) else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            providerTurnActive = false
            lastProviderTerminal = .failed
            return try fail(
                code: Self.providerFailureCode(source["error"]),
                message: "provider terminal",
                wording: (source["error"] is [String: Any])
                    ? .internalServerError
                    : .withoutProviderPayload
            )
        }
        guard !providerTurnActive,
            status == lastProviderTerminal,
            source["output"] is [Any],
            source["usage"] is [String: Any]
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let response = try finalResponse(
            sourceJSON: responseJSON,
            terminal: status,
            usage: usage
        )
        let terminalEvent = "response.\(status.rawValue)"
        let terminalFrame = try frame(terminalEvent, payload: ["response": response])
        terminalState = status == .failed ? .failed : .completed
        return [terminalFrame]
    }

    package mutating func fail(
        code: String = "server_error",
        message: String,
        wording: FailureWording = .internalServerError
    ) throws -> [Data] {
        // The provider's own text never reaches the client: `message` is a
        // diagnostic for the caller's logs only. Client-visible wording stays
        // a closed set of strings this gateway authors.
        _ = message
        guard terminalState == .open,
            ["context_length_exceeded", "server_error"].contains(code)
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let response = try failedResponse(code: code, message: wording.text)

        let frames = [
            try frame(
                "error",
                payload: [
                    "code": code,
                    "message": wording.text,
                    "param": NSNull(),
                ]
            ),
            try frame("response.failed", payload: ["response": response]),
        ]
        terminalState = .failed
        return frames
    }

    /// The public contract only carries two failure codes, so an unknown
    /// provider code degrades to `server_error` rather than leaking through.
    static func providerFailureCode(_ error: Any?) -> String {
        guard let error = error as? [String: Any],
            error["code"] as? String == "context_length_exceeded"
        else {
            return "server_error"
        }
        return "context_length_exceeded"
    }

    /// Client-visible failure wording this gateway authors. Providers may
    /// fail a response while leaving the error object null, and an
    /// upstream stream may end before a terminal event arrives — both
    /// observed native-provider behaviors. Naming those cases beats the blanket "Internal
    /// server error" that hid the cause for hours, without echoing provider
    /// text.
    package enum FailureWording: Sendable {
        case internalServerError
        case withoutProviderPayload
        case upstreamEndedBeforeCompletion

        var text: String {
            switch self {
            case .internalServerError:
                "Internal server error"
            case .withoutProviderPayload:
                "The provider failed the response without an error payload."
            case .upstreamEndedBeforeCompletion:
                "Upstream stream ended before completion"
            }
        }
    }
}
