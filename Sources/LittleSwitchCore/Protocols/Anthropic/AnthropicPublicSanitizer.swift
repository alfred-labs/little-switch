import LittleSwitchWire

enum AnthropicPublicSanitizer {
    static func block(_ source: JSONObject) throws -> JSONObject? {
        let block = try anthropicDecode(AnthropicContentBlock.self, from: anthropicJSON(source))
        let value: JSONValue
        switch block {
        case .text(var block):
            if case .value(let citations) = block.citations {
                block.citations = .value(try citations.compactMap(citation))
            }
            block.additionalFields = [:]
            value = try block.wireJSON()
        case .thinking(var block):
            block.additionalFields = [:]
            value = try block.wireJSON()
        case .redactedThinking(var block):
            block.additionalFields = [:]
            value = try block.wireJSON()
        case .toolUse(var block):
            try validateTool(id: block.id, name: block.name, input: block.input)
            block.caller = try caller(block.caller)
            block.additionalFields = [:]
            value = try block.wireJSON()
        case .serverToolUse(var block):
            try validateTool(id: block.id, name: block.name.rawValue, input: block.input)
            block.caller = try caller(block.caller)
            block.additionalFields = [:]
            value = try block.wireJSON()
        case .webSearchToolResult(var block):
            guard !block.toolUseId.isEmpty else { throw AnthropicWebSearch.Error.invalidMessage }
            block.caller = try caller(block.caller)
            block.content = publicSearchContent(block.content)
            block.additionalFields = [:]
            value = try block.wireJSON()
        case .unknown(let type, _):
            guard !type.isEmpty else { throw AnthropicWebSearch.Error.invalidMessage }
            return nil
        }
        return value.anthropicObject
    }

    static func delta(_ source: JSONObject) throws -> JSONObject? {
        let delta = try anthropicDecode(AnthropicContentDelta.self, from: anthropicJSON(source))
        let value: JSONValue
        switch delta {
        case .textDelta(var delta):
            delta.additionalFields = [:]
            value = try delta.wireJSON()
        case .thinkingDelta(var delta):
            delta.additionalFields = [:]
            value = try delta.wireJSON()
        case .signatureDelta(var delta):
            delta.additionalFields = [:]
            value = try delta.wireJSON()
        case .inputJsonDelta(var delta):
            delta.additionalFields = [:]
            value = try delta.wireJSON()
        case .citationsDelta(var delta):
            if case .absent = delta.citation { return nil }
            guard case .value(let raw) = delta.citation else { throw AnthropicWebSearch.Error.invalidMessage }
            let decoded = try anthropicDecode(AnthropicCitation.self, from: raw)
            guard let citation = try citation(decoded) else { return nil }
            delta.citation = .value(try citation.wireJSON())
            delta.additionalFields = [:]
            value = try delta.wireJSON()
        case .unknown(let type, _):
            guard !type.isEmpty else { throw AnthropicWebSearch.Error.invalidMessage }
            return nil
        }
        return value.anthropicObject
    }

    private static func validateTool(id: String, name: String, input: JSONValue?) throws {
        guard !id.isEmpty, !name.isEmpty, input?.object != nil else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
    }

    private static func publicSearchContent(_ content: AnthropicWebSearchContent) -> AnthropicWebSearchContent {
        switch content {
        case .variant1(var error):
            error.additionalFields = [:]
            return .variant1(error)
        case .variant2(let results):
            return .variant2(
                results.map { result in
                    var result = result
                    result.additionalFields = [:]
                    return result
                })
        }
    }
}

extension AnthropicPublicSanitizer {
    private static func caller(_ value: JSONPresence<JSONValue>) throws -> JSONPresence<JSONValue> {
        switch value {
        case .absent: return .absent
        case .null: throw AnthropicWebSearch.Error.invalidMessage
        case .value(let raw):
            let caller = try anthropicDecode(AnthropicCaller.self, from: raw)
            switch caller {
            case .direct(var caller):
                caller.additionalFields = [:]
                return .value(try caller.wireJSON())
            case .codeExecution20250825(var caller):
                guard !caller.toolId.isEmpty else { throw AnthropicWebSearch.Error.invalidMessage }
                caller.additionalFields = [:]
                return .value(try caller.wireJSON())
            case .codeExecution20260120(var caller):
                guard !caller.toolId.isEmpty else { throw AnthropicWebSearch.Error.invalidMessage }
                caller.additionalFields = [:]
                return .value(try caller.wireJSON())
            case .unknown:
                return .absent
            }
        }
    }

    private static func citation(_ citation: AnthropicCitation) throws -> AnthropicCitation? {
        switch citation {
        case .charLocation(var citation):
            try validateIndices([citation.documentIndex, citation.startCharIndex, citation.endCharIndex])
            citation.additionalFields = [:]
            return .charLocation(citation)
        case .pageLocation(var citation):
            try validateIndices([citation.documentIndex, citation.startPageNumber, citation.endPageNumber])
            citation.additionalFields = [:]
            return .pageLocation(citation)
        case .contentBlockLocation(var citation):
            try validateIndices([citation.documentIndex, citation.startBlockIndex, citation.endBlockIndex])
            citation.additionalFields = [:]
            return .contentBlockLocation(citation)
        case .webSearchResultLocation(var citation):
            guard citation.title != nil else { throw AnthropicWebSearch.Error.invalidMessage }
            citation.additionalFields = [:]
            return .webSearchResultLocation(citation)
        case .searchResultLocation(var citation):
            try validateIndices([citation.searchResultIndex, citation.startBlockIndex, citation.endBlockIndex])
            citation.additionalFields = [:]
            return .searchResultLocation(citation)
        case .unknown:
            return nil
        }
    }

    private static func validateIndices(_ indices: [JSONNumber]) throws {
        for number in indices { _ = try anthropicTokenCount(number) }
    }
}
