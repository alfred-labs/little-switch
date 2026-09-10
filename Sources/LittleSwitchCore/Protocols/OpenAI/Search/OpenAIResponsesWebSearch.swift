import Foundation
import LittleSwitchSearch

package struct PreparedResponsesWebSearchRequest: Equatable, Sendable {
    let upstreamBody: Data
    let originalBody: Data
    let originalModel: String
    let originalToolsJSON: Data
    let originalInputJSON: Data
    let streaming: Bool
    let maximumUses: Int
    let searchOptions: WebSearchFilterOptions
    var toolBindings: [String: ResponsesToolNamespaces.Binding] = [:]
    var droppedMailCount: Int = 0
    var toolSearchContract: ResponsesClientToolSearchContract?
    var privateToolName: String?

    package init(
        upstreamBody: Data,
        originalBody: Data,
        originalModel: String,
        originalToolsJSON: Data,
        originalInputJSON: Data,
        streaming: Bool,
        maximumUses: Int,
        searchOptions: WebSearchFilterOptions = WebSearchFilterOptions(),
        toolBindings: [String: ResponsesToolNamespaces.Binding] = [:],
        droppedMailCount: Int = 0,
        toolSearchContract: ResponsesClientToolSearchContract? = nil,
        privateToolName: String? = "web_search"
    ) {
        self.upstreamBody = upstreamBody
        self.originalBody = originalBody
        self.originalModel = originalModel
        self.originalToolsJSON = originalToolsJSON
        self.originalInputJSON = originalInputJSON
        self.streaming = streaming
        self.maximumUses = maximumUses
        self.searchOptions = searchOptions
        self.toolBindings = toolBindings
        self.droppedMailCount = droppedMailCount
        self.toolSearchContract = toolSearchContract
        self.privateToolName = privateToolName
    }
}

package enum OpenAIResponsesWebSearch {
    enum Error: Swift.Error, Equatable {
        case invalidResponse
        /// The upstream response body ended before a terminal event
        /// (`response.completed`, `response.incomplete`, `response.failed`)
        /// arrived: a connection dropped mid-turn, not an unparseable frame.
        case streamEndedBeforeTerminal
    }

    private static let toolName = "web_search"

    static func prepare(
        body: Data,
        targetModel: String,
        configuration: WebSearchConfiguration
    ) throws -> PreparedResponsesWebSearchRequest? {
        let original = try object(from: body)
        if let value = original["tools"], !(value is [[String: Any]]) { throw Error.invalidResponse }
        let toolSearch = try OpenAIResponsesToolSearch.prepare(body: body)
        let object = try toolSearch.map { try self.object(from: $0.upstreamBody) } ?? original
        try ProviderToolRequestPolicy.responses(object, allowingWebSearch: true)
        let tools = (object["tools"] as? [[String: Any]]) ?? []
        let searchTool = tools.first(where: isBuiltInSearchTool)
        // This bridge only offers external search. An explicit refusal
        // removes that tool without disabling collaboration adaptation.
        let engagingSearchTool =
            configuration.provider == .disabled || searchTool?["external_web_access"] as? Bool == false
            ? nil : searchTool
        // Namespace tools still need flattening and public-name restoration,
        // and bridge-owned history still needs conversion, without search.
        let needsAdaptation =
            tools.contains { $0["type"] as? String == "namespace" }
            || inputContainsOwnedItems(object["input"])
            || toolSearch != nil
        guard searchTool != nil || needsAdaptation else {
            return nil
        }
        try ProviderToolRequestPolicy.responses(object, allowingWebSearch: true, allowingCustom: false)
        guard
            !ResponsesConversationReferences.hasServerState(in: object),
            let originalModel = object["model"] as? String,
            !originalModel.isEmpty,
            let originalInput = original["input"],
            let input = object["input"],
            input is String || input is [[String: Any]]
        else {
            throw Error.invalidResponse
        }
        let maximumUses: Int
        if let requestedMaximum = object["max_tool_calls"] {
            guard let requestedMaximum = requestedMaximum as? Int,
                requestedMaximum > 0
            else {
                throw Error.invalidResponse
            }
            maximumUses = min(configuration.maximumUses, requestedMaximum)
        } else {
            maximumUses = configuration.maximumUses
        }

        var privateTools = tools.filter { tool in
            !isBuiltInSearchTool(tool)
        }
        let privateToolName = engagingSearchTool.map { _ in
            ResponsesPrivateSearchBinding.name(tools: privateTools, input: input)
        }
        if let privateToolName {
            var declaration = privateSearchTool
            declaration["name"] = privateToolName
            privateTools.insert(declaration, at: 0)
        }

        var upstream = object
        upstream["model"] = targetModel
        upstream["stream"] = false
        upstream["parallel_tool_calls"] = false
        upstream["tools"] = privateTools
        let forcesBuiltInSearch = (upstream["tool_choice"] as? [String: Any]).map(isBuiltInSearchTool) ?? false
        if engagingSearchTool == nil {
            let removedSearchName = privateTools.contains { isPrivateSearchTool($0) } ? nil : "web_search"
            upstream["tool_choice"] = toolChoiceWithoutSearch(
                upstream["tool_choice"], remainingTools: privateTools, privateToolName: removedSearchName
            )
        } else if forcesBuiltInSearch {
            upstream["tool_choice"] = ["type": "function", "name": privateToolName as Any]
        }
        let resolvedSearchOptions: WebSearchFilterOptions
        if let engagingSearchTool {
            resolvedSearchOptions = try searchOptions(from: engagingSearchTool)
        } else {
            resolvedSearchOptions = WebSearchFilterOptions()
        }
        let normalized = try OpenAIResponsesNativeNamespacing.normalize(
            try data(from: upstream)
        )
        return PreparedResponsesWebSearchRequest(
            upstreamBody: normalized.body,
            originalBody: body,
            originalModel: originalModel,
            originalToolsJSON: try fragmentData(from: original["tools"] ?? []),
            originalInputJSON: try fragmentData(from: originalInput),
            streaming: object["stream"] as? Bool ?? false,
            maximumUses: engagingSearchTool == nil ? 0 : maximumUses,
            searchOptions: resolvedSearchOptions,
            toolBindings: normalized.toolBindings,
            droppedMailCount: normalized.droppedMailCount,
            toolSearchContract: toolSearch?.contract,
            privateToolName: privateToolName
        )
    }

    /// True when the replayed history carries items this bridge owns.
    private static func inputContainsOwnedItems(_ input: Any?) -> Bool {
        guard let items = input as? [[String: Any]] else {
            return false
        }
        return items.contains { item in
            let type = item["type"] as? String
            return type == "web_search_call" || type == "agent_message" || item["namespace"] is String
        }
    }

    static func streamingRequestBody(_ body: Data) throws -> Data {
        var object = try object(from: body)
        object["stream"] = true
        return try data(from: object)
    }

    private static var privateSearchTool: [String: Any] {
        [
            "type": "function",
            "name": toolName,
            "description": "Search the web for current information.",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "The search query.",
                    ]
                ],
                "required": ["query"],
            ],
        ]
    }

    static func isBuiltInSearchTool(_ tool: [String: Any]) -> Bool {
        ["web_search", "web_search_preview", "web_search_preview_2025_03_11"].contains(tool["type"] as? String ?? "")
    }

    private static func searchOptions(
        from tool: [String: Any]
    ) throws -> WebSearchFilterOptions {
        let includeDomains: [String]?
        let excludeDomains: [String]?
        if let filtersValue = tool["filters"] {
            guard let filters = filtersValue as? [String: Any] else {
                throw Error.invalidResponse
            }
            includeDomains = try domainList(filters["allowed_domains"])
            excludeDomains = try domainList(filters["blocked_domains"])
        } else {
            includeDomains = nil
            excludeDomains = nil
        }
        let location = try approximateLocation(tool["user_location"])
        return WebSearchFilterOptions(
            includeDomains: includeDomains,
            excludeDomains: excludeDomains,
            location: location.location,
            country: location.country
        )
    }

    private static func domainList(_ value: Any?) throws -> [String]? {
        guard let value else {
            return nil
        }
        guard let domains = value as? [String] else {
            throw Error.invalidResponse
        }
        return try domains.map { value in
            let domain = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !domain.isEmpty else {
                throw Error.invalidResponse
            }
            return domain
        }
    }

    private static func approximateLocation(
        _ value: Any?
    ) throws -> (location: String?, country: String?) {
        guard let value else {
            return (nil, nil)
        }
        guard let object = value as? [String: Any],
            object["type"] as? String == "approximate"
        else {
            throw Error.invalidResponse
        }
        let city = try optionalNonemptyString(object["city"])
        let region = try optionalNonemptyString(object["region"])
        let country = try optionalNonemptyString(object["country"])
        _ = try optionalNonemptyString(object["timezone"])
        let location = [city, region].compactMap(\.self).joined(separator: ", ")
        return (location.isEmpty ? nil : location, country)
    }

    private static func optionalNonemptyString(_ value: Any?) throws -> String? {
        guard let value else {
            return nil
        }
        guard let string = value as? String else {
            throw Error.invalidResponse
        }
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw Error.invalidResponse
        }
        return normalized
    }

    private static func object(from data: Data) throws -> [String: Any] {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw Error.invalidResponse
        }
        guard let object = value as? [String: Any] else {
            throw Error.invalidResponse
        }
        return object
    }

    private static func data(from object: [String: Any]) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    private static func fragmentData(from value: Any) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: value,
            options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
        )
    }
}
