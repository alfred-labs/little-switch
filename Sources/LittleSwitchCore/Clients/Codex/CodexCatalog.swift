import Foundation

public struct CodexTruncationPolicy: Encodable, Equatable, Sendable {
    public var mode: String
    public var limit: Int

    public init(mode: String, limit: Int) {
        self.mode = mode
        self.limit = limit
    }
}

public struct CodexReasoningEffortPreset: Encodable, Equatable, Sendable {
    public var effort: String
    public var description: String

    public init(effort: String, description: String) {
        self.effort = effort
        self.description = description
    }
}

public struct CodexCatalogModel: Encodable, Equatable, Sendable {
    public var slug: String
    public var displayName: String
    public var description: String
    public var defaultReasoningLevel: String?
    public var supportedReasoningLevels: [CodexReasoningEffortPreset]
    public var shellType: String
    /// Explicitly override Codex's code-mode feature default for managed models.
    public var toolMode: String { "direct" }
    public var visibility: String
    public var supportedInAPI: Bool
    public var priority: Int
    public var additionalSpeedTiers: [String]
    public var availabilityNUX: String?
    public var upgrade: String?
    public var baseInstructions: String
    public var modelMessages: String?
    public var supportsReasoningSummaries: Bool
    public var defaultReasoningSummary: String
    public var supportVerbosity: Bool
    public var defaultVerbosity: String?
    public var applyPatchToolType: String?
    public var webSearchToolType: String
    public var truncationPolicy: CodexTruncationPolicy
    public var supportsParallelToolCalls: Bool
    public var supportsImageDetailOriginal: Bool
    public var contextWindow: Int
    public var maxContextWindow: Int
    public var autoCompactTokenLimit: Int?
    public var effectiveContextWindowPercent: Int
    public var experimentalSupportedTools: [String]
    public var inputModalities: [String]
    public var supportsSearchTool: Bool
    public var multiAgentVersion: String?
    public var autoReviewModelOverride: String

    private enum CodingKeys: String, CodingKey {
        case slug
        case displayName = "display_name"
        case description
        case defaultReasoningLevel = "default_reasoning_level"
        case supportedReasoningLevels = "supported_reasoning_levels"
        case shellType = "shell_type"
        case toolMode = "tool_mode"
        case visibility
        case supportedInAPI = "supported_in_api"
        case priority
        case additionalSpeedTiers = "additional_speed_tiers"
        case availabilityNUX = "availability_nux"
        case upgrade
        case baseInstructions = "base_instructions"
        case modelMessages = "model_messages"
        case supportsReasoningSummaries = "supports_reasoning_summaries"
        case defaultReasoningSummary = "default_reasoning_summary"
        case supportVerbosity = "support_verbosity"
        case defaultVerbosity = "default_verbosity"
        case applyPatchToolType = "apply_patch_tool_type"
        case webSearchToolType = "web_search_tool_type"
        case truncationPolicy = "truncation_policy"
        case supportsParallelToolCalls = "supports_parallel_tool_calls"
        case supportsImageDetailOriginal = "supports_image_detail_original"
        case contextWindow = "context_window"
        case maxContextWindow = "max_context_window"
        case autoCompactTokenLimit = "auto_compact_token_limit"
        case effectiveContextWindowPercent = "effective_context_window_percent"
        case experimentalSupportedTools = "experimental_supported_tools"
        case inputModalities = "input_modalities"
        case supportsSearchTool = "supports_search_tool"
        case multiAgentVersion = "multi_agent_version"
        case autoReviewModelOverride = "auto_review_model_override"
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(slug, forKey: .slug)
        try values.encode(displayName, forKey: .displayName)
        try values.encode(description, forKey: .description)
        try encode(defaultReasoningLevel, in: &values, forKey: .defaultReasoningLevel)
        try values.encode(supportedReasoningLevels, forKey: .supportedReasoningLevels)
        try values.encode(shellType, forKey: .shellType)
        try values.encode(toolMode, forKey: .toolMode)
        try values.encode(visibility, forKey: .visibility)
        try values.encode(supportedInAPI, forKey: .supportedInAPI)
        try values.encode(priority, forKey: .priority)
        try values.encode(additionalSpeedTiers, forKey: .additionalSpeedTiers)
        try encode(availabilityNUX, in: &values, forKey: .availabilityNUX)
        try encode(upgrade, in: &values, forKey: .upgrade)
        try values.encode(baseInstructions, forKey: .baseInstructions)
        try encode(modelMessages, in: &values, forKey: .modelMessages)
        try values.encode(supportsReasoningSummaries, forKey: .supportsReasoningSummaries)
        try values.encode(defaultReasoningSummary, forKey: .defaultReasoningSummary)
        try values.encode(supportVerbosity, forKey: .supportVerbosity)
        try encode(defaultVerbosity, in: &values, forKey: .defaultVerbosity)
        try encode(applyPatchToolType, in: &values, forKey: .applyPatchToolType)
        try values.encode(webSearchToolType, forKey: .webSearchToolType)
        try values.encode(truncationPolicy, forKey: .truncationPolicy)
        try values.encode(supportsParallelToolCalls, forKey: .supportsParallelToolCalls)
        try values.encode(supportsImageDetailOriginal, forKey: .supportsImageDetailOriginal)
        try values.encode(contextWindow, forKey: .contextWindow)
        try values.encode(maxContextWindow, forKey: .maxContextWindow)
        if let autoCompactTokenLimit {
            try values.encode(autoCompactTokenLimit, forKey: .autoCompactTokenLimit)
        } else {
            try values.encodeNil(forKey: .autoCompactTokenLimit)
        }
        try values.encode(effectiveContextWindowPercent, forKey: .effectiveContextWindowPercent)
        try values.encode(experimentalSupportedTools, forKey: .experimentalSupportedTools)
        try values.encode(inputModalities, forKey: .inputModalities)
        try values.encode(supportsSearchTool, forKey: .supportsSearchTool)
        try encode(multiAgentVersion, in: &values, forKey: .multiAgentVersion)
        try values.encode(autoReviewModelOverride, forKey: .autoReviewModelOverride)
    }

    private func encode(
        _ value: String?,
        in values: inout KeyedEncodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws {
        if let value {
            try values.encode(value, forKey: key)
        } else {
            try values.encodeNil(forKey: key)
        }
    }
}

extension String {
    /// Case-insensitive slug identity shared by managed and native entries.
    fileprivate var trimmedSlugKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct CodexModelCatalog: Encodable, Equatable, Sendable {
    public var models: [CodexCatalogModel]

    public init(models: [CodexCatalogModel]) {
        self.models = models
    }
}

public enum CodexCatalog {
    public enum Error: Swift.Error, Equatable {
        case empty
        case unavailableAutoReviewModel
    }

    /// Separate from Codex's native reviewer so custom routing cannot capture
    /// approval requests made by native OpenAI models.
    package static let managedAutoReviewModel = "little-switch-auto-review"
    package static let legacyManagedAutoReviewModel = "codex-auto-review"

    public static let baseInstructions =
        "You are Codex, a coding agent. You and the user share the same workspace and collaborate to achieve the user's goals."

    public static let supportedReasoningLevels = [
        CodexReasoningEffortPreset(
            effort: "none",
            description: "Disables reasoning for the lowest latency"
        ),
        CodexReasoningEffortPreset(
            effort: "minimal",
            description: "Minimal reasoning for simple tasks"
        ),
        CodexReasoningEffortPreset(
            effort: "low",
            description: "Fast responses with lighter reasoning"
        ),
        CodexReasoningEffortPreset(
            effort: "medium",
            description: "Balances speed and reasoning depth for everyday tasks"
        ),
        CodexReasoningEffortPreset(
            effort: "high",
            description: "Greater reasoning depth for complex problems"
        ),
        CodexReasoningEffortPreset(
            effort: "xhigh",
            description: "Extra high reasoning depth for complex problems"
        ),
        CodexReasoningEffortPreset(
            effort: "max",
            description: "Maximum reasoning depth for the hardest problems"
        ),
        CodexReasoningEffortPreset(
            effort: "ultra",
            description: "Maximum reasoning with automatic task delegation"
        ),
    ]

    /// Codex surfaces the slug itself in its model picker, so it stays the
    /// readable `provider/model` pair; RoutingSnapshot resolves it back by
    /// exact string match. Provider names are unique case-insensitively
    /// (enforced on save), so the lowercased pair is unique too.
    package static func slug(for target: CodexModelTarget) -> String {
        target.provider.reference(to: target.model.id).lowercased()
    }

    public static func make(
        providers: [Provider],
        configuration: CodexConfiguration
    ) throws -> CodexModelCatalog {
        var targets = configuration.exposedModels(in: providers)
        guard !targets.isEmpty else {
            throw Error.empty
        }
        if let defaultModel = configuration.resolvedDefaultModel(in: providers) {
            if let index = targets.firstIndex(where: { $0.mapping == defaultModel }) {
                targets.insert(targets.remove(at: index), at: 0)
            }
        }
        var models = targets.enumerated().map { index, target in
            makeModel(target: target, priority: index)
        }
        guard let reviewerTarget = configuration.resolvedAutoReviewTarget(in: providers) else {
            throw Error.unavailableAutoReviewModel
        }
        // Codex selects the reviewer separately from the task. Its hidden entry
        // carries the actual review model's capabilities and identity so profile
        // signatures also detect reviewer changes between equal-capacity models.
        var reviewer = makeModel(target: reviewerTarget, priority: models.count)
        reviewer.slug = managedAutoReviewModel
        reviewer.displayName = managedAutoReviewModel
        reviewer.description = "Approval reviews via \(reviewerTarget.displayName)"
        reviewer.visibility = "hide"
        models.append(reviewer)
        return CodexModelCatalog(models: models)
    }

    package static func encode(
        providers: [Provider],
        configuration: CodexConfiguration
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(make(providers: providers, configuration: configuration))
        data.append(UInt8(ascii: "\n"))
        return data
    }

    /// Encodes the managed catalog merged with Codex's native entries. The
    /// LittleSwitch entries win slug collisions and keep their API support;
    /// native entries are marked ChatGPT-only and preserved field-for-field.
    package static func encode(
        providers: [Provider],
        configuration: CodexConfiguration,
        nativeCatalogData: Data?
    ) throws -> Data {
        try mergedData(
            managedData: encode(providers: providers, configuration: configuration),
            nativeCatalogData: nativeCatalogData
        )
    }

    /// Merges an encoded managed catalog with raw native entries. Pure so
    /// status comparisons can rebuild the exact merged bytes from the stored
    /// native snapshot without re-probing Codex.
    package static func mergedData(
        managedData: Data,
        nativeCatalogData: Data?
    ) throws -> Data {
        guard
            let root = try? JSONSerialization.jsonObject(with: managedData) as? [String: Any],
            let managed = root["models"] as? [[String: Any]]
        else {
            throw Error.empty
        }
        var data = try JSONSerialization.data(
            withJSONObject: try mergedRoot(managed: managed, nativeCatalogData: nativeCatalogData),
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(UInt8(ascii: "\n"))
        return data
    }

    private static func mergedRoot(
        managed: [[String: Any]],
        nativeCatalogData: Data?
    ) throws -> [String: Any] {
        var managedEntries = managed
        // The hidden reviewer always trails the managed list; native models
        // slot in before it so the visible picker order is managed, native.
        var reviewer: [String: Any]?
        let reviewerSlugs = [managedAutoReviewModel, legacyManagedAutoReviewModel]
        if let slug = managedEntries.last?["slug"] as? String, reviewerSlugs.contains(slug) {
            reviewer = managedEntries.removeLast()
        }
        var entries = managedEntries
        var seen = Set(entries.compactMap { ($0["slug"] as? String)?.trimmedSlugKey })
        if let reviewer, let slug = reviewer["slug"] as? String {
            seen.insert(slug.trimmedSlugKey)
        }
        let nativeRoot = nativeCatalogData.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        if let nativeModels = nativeRoot?["models"] as? [[String: Any]] {
            for var entry in nativeModels {
                guard let slug = entry["slug"] as? String else {
                    continue
                }
                let key = slug.trimmedSlugKey
                guard !key.isEmpty, seen.insert(key).inserted else {
                    continue
                }
                entry["supported_in_api"] = false
                entries.append(entry)
            }
        }
        if let reviewer {
            entries.append(reviewer)
        }
        // Codex sorts the picker by priority with a stable sort; native
        // entries keep their upstream priorities (1, 3, 6…), which would
        // interleave with the managed block. Renumber by position so the
        // file order — managed first, natives, hidden reviewer last — is
        // exactly what the sorted picker displays.
        for index in entries.indices {
            entries[index]["priority"] = index
        }
        return ["models": entries]
    }

    private static func makeModel(
        target: CodexModelTarget,
        priority: Int
    ) -> CodexCatalogModel {
        let contextWindow = target.model.effectiveContextWindow ?? 128_000
        return CodexCatalogModel(
            slug: slug(for: target),
            displayName: target.displayName,
            description: ProductIdentity.displayName,
            defaultReasoningLevel: "medium",
            supportedReasoningLevels: supportedReasoningLevels,
            shellType: "default",
            visibility: "list",
            supportedInAPI: true,
            priority: priority,
            additionalSpeedTiers: [],
            availabilityNUX: nil,
            upgrade: nil,
            baseInstructions: baseInstructions,
            modelMessages: nil,
            supportsReasoningSummaries: false,
            defaultReasoningSummary: "auto",
            supportVerbosity: false,
            defaultVerbosity: nil,
            applyPatchToolType: nil,
            webSearchToolType: "text",
            truncationPolicy: CodexTruncationPolicy(mode: "bytes", limit: 10_000),
            supportsParallelToolCalls: true,
            supportsImageDetailOriginal: false,
            contextWindow: contextWindow,
            maxContextWindow: contextWindow,
            autoCompactTokenLimit: nil,
            effectiveContextWindowPercent: 95,
            experimentalSupportedTools: [],
            inputModalities: target.provider.imageInputsAccepted(for: target.model)
                ? ["text", "image"]
                : ["text"],
            supportsSearchTool: false,
            multiAgentVersion: "v2",
            autoReviewModelOverride: managedAutoReviewModel
        )
    }
}
