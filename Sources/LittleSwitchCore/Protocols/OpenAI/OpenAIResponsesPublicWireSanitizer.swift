import Foundation
import LittleSwitchSearch
import LittleSwitchWire

extension OpenAIResponsesPublicSanitizer {
    static func wireItem(_ json: JSONValue) throws -> JSONValue {
        let item = try responsesWireDecode(OpenAIResponsesOutputItem.self, json: json)
        switch item {
        case .message(var message):
            guard !message.id.isEmpty, let content = message.content else { throw invalidWireItem }
            message.content = try content.map(wireContentPart)
            message.phase = publicPresence(message.phase)
            message.status = publicPresence(message.status)
            if var metadata = message.internalChatMessageMetadataPassthrough, metadata.turnId != nil {
                metadata.additionalFields = [:]
                message.internalChatMessageMetadataPassthrough = metadata
            } else {
                message.internalChatMessageMetadataPassthrough = nil
            }
            message.additionalFields = [:]
            return try message.wireJSON()
        case .functionCall(var call):
            guard call.id?.isEmpty == false, !call.callId.isEmpty, !call.name.isEmpty else { throw invalidWireItem }
            call.namespace = publicPresence(call.namespace)
            call.status = publicPresence(call.status)
            if var metadata = call.internalChatMessageMetadataPassthrough, metadata.turnId != nil {
                metadata.additionalFields = [:]
                call.internalChatMessageMetadataPassthrough = metadata
            } else {
                call.internalChatMessageMetadataPassthrough = nil
            }
            if let encrypted = call.encryptedFunctionArgs.value {
                call.encryptedFunctionArgs = .value(encrypted)
            } else if ResponsesAgentMail.requiresPlaintext(namespace: call.namespace.value, name: call.name) {
                call.encryptedFunctionArgs = .value([])
            } else {
                call.encryptedFunctionArgs = .absent
            }
            call.additionalFields = [:]
            return try call.wireJSON()
        case .customToolCall(var call):
            guard call.id?.isEmpty == false, !call.callId.isEmpty, !call.name.isEmpty else { throw invalidWireItem }
            call.namespace = publicPresence(call.namespace)
            call.status = publicPresence(call.status)
            if var metadata = call.internalChatMessageMetadataPassthrough, metadata.turnId != nil {
                metadata.additionalFields = [:]
                call.internalChatMessageMetadataPassthrough = metadata
            } else {
                call.internalChatMessageMetadataPassthrough = nil
            }
            call.additionalFields = [:]
            return try call.wireJSON()
        case .reasoning(var reasoning):
            guard !reasoning.id.isEmpty else { throw invalidWireItem }
            reasoning.status = publicPresence(reasoning.status)
            reasoning.summary = try wireReasoningSummary(reasoning.summary ?? [])
            if let content = reasoning.content.value {
                reasoning.content = .value(try wireReasoningContent(content))
            } else {
                reasoning.content = .absent
            }
            if var metadata = reasoning.internalChatMessageMetadataPassthrough, metadata.turnId != nil {
                metadata.additionalFields = [:]
                reasoning.internalChatMessageMetadataPassthrough = metadata
            } else {
                reasoning.internalChatMessageMetadataPassthrough = nil
            }
            reasoning.additionalFields = [:]
            return try reasoning.wireJSON()
        case .webSearchCall(var search):
            guard !search.id.isEmpty else { throw invalidWireItem }
            search.status = publicPresence(search.status)
            search.action = try search.action.map(wireSearchAction)
            search.additionalFields = [:]
            return try search.wireJSON()
        case .toolSearchCall(var search):
            guard !search.id.isEmpty, search.execution == .client,
                search.callId.value?.isEmpty == false, search.arguments.value?.object != nil
            else { throw invalidWireItem }
            search.status = publicPresence(search.status)
            search.additionalFields = [:]
            return try search.wireJSON()
        case .unknown:
            throw invalidWireItem
        }
    }

    static func wireContentPart(_ json: JSONValue) throws -> JSONValue {
        try wireContentPart(responsesWireDecode(OpenAIResponsesContentPart.self, json: json)).wireJSON()
    }

    private static func wireContentPart(_ part: OpenAIResponsesContentPart) throws -> OpenAIResponsesContentPart {
        switch part {
        case .outputText(var text):
            text.annotations = .value(try (text.annotations.value ?? []).map(wireAnnotation))
            text.logprobs = .value(try (text.logprobs.value ?? []).map(wireLogprob))
            text.additionalFields = [:]
            return .outputText(text)
        case .refusal(var refusal):
            refusal.additionalFields = [:]
            return .refusal(refusal)
        case .unknown:
            throw invalidWireItem
        }
    }

    static func wireAnnotation(_ annotation: OpenAITextAnnotation) throws -> OpenAITextAnnotation {
        switch annotation {
        case .urlCitation(var citation):
            _ = try citation.startIndex.map(responsesWireIndex)
            _ = try citation.endIndex.map(responsesWireIndex)
            citation.additionalFields = [:]
            return .urlCitation(citation)
        case .fileCitation(var citation):
            _ = try citation.index.map(responsesWireIndex)
            citation.additionalFields = [:]
            return .fileCitation(citation)
        case .containerFileCitation(var citation):
            _ = try citation.startIndex.map(responsesWireIndex)
            _ = try citation.endIndex.map(responsesWireIndex)
            citation.additionalFields = [:]
            return .containerFileCitation(citation)
        case .filePath(var citation):
            _ = try citation.index.map(responsesWireIndex)
            citation.additionalFields = [:]
            return .filePath(citation)
        case .unknown:
            throw invalidWireItem
        }
    }

    private static func wireLogprob(_ value: OpenAIResponsesLogprob) throws -> OpenAIResponsesLogprob {
        var value = value
        try validateWireBytes(value.bytes.value)
        value.topLogprobs = try value.topLogprobs?.map { top in
            var top = top
            try validateWireBytes(top.bytes.value)
            top.additionalFields = [:]
            return top
        }
        value.additionalFields = [:]
        return value
    }

    private static func validateWireBytes(_ bytes: [JSONNumber]?) throws {
        for byte in bytes ?? [] where try responsesWireIndex(byte) > 255 { throw invalidWireItem }
    }

    private static func wireSearchAction(
        _ action: OpenAIWebSearchAction
    ) throws -> OpenAIWebSearchAction {
        switch action {
        case .search(var search):
            guard (search.sources?.count ?? 0) <= 100 else { throw invalidWireItem }
            search.sources = try search.sources?.map { source in
                guard let validated = WebSearchResultShaping.validated(title: "Source", url: source.url, content: ""),
                    validated.url == source.url
                else { throw invalidWireItem }
                var source = source
                source.additionalFields = [:]
                return source
            }
            search.additionalFields = [:]
            return .search(search)
        case .openPage(var page):
            // The public contract has never accepted an explicit null URL.
            guard case .null = page.url else {
                page.additionalFields = [:]
                return .openPage(page)
            }
            throw invalidWireItem
        case .findInPage(var find):
            find.additionalFields = [:]
            return .findInPage(find)
        case .unknown:
            throw invalidWireItem
        }
    }

    private static func wireReasoningContent(_ content: JSONValue) throws -> JSONValue {
        guard let parts = content.array, parts.allSatisfy({ $0.object != nil }) else { throw invalidWireItem }
        return .array(
            try parts.compactMap { part in
                guard
                    part.object?[OpenAIResponsesReasoningContentPart.Key.type.rawValue]?.string
                        == OpenAIResponsesReasoningContentPartType.reasoningText.rawValue
                else { return nil }
                var content = try responsesWireDecode(OpenAIResponsesReasoningContentPart.self, json: part)
                content.additionalFields = [:]
                return try content.wireJSON()
            })
    }

    private static func wireReasoningSummary(_ parts: [JSONValue]) throws -> [JSONValue] {
        guard parts.allSatisfy({ $0.object != nil }) else { throw invalidWireItem }
        return try parts.compactMap { json in
            guard
                json.object?[OpenAIResponsesSummaryPart.Key.type.rawValue]?.string
                    == OpenAIResponsesSummaryPartType.summaryText.rawValue
            else { return nil }
            var part = try responsesWireDecode(OpenAIResponsesSummaryPart.self, json: json)
            part.additionalFields = [:]
            return try part.wireJSON()
        }
    }

    private static func publicPresence<Value: Sendable>(_ presence: JSONPresence<Value>) -> JSONPresence<Value> {
        presence.value.map { .value($0) } ?? .absent
    }

    private static var invalidWireItem: OpenAIResponsesWebSearch.Error { .invalidResponse }
}
