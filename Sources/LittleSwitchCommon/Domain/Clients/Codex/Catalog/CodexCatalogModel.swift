import Foundation

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
    package init(
        slug: String,
        displayName: String,
        description: String,
        defaultReasoningLevel: String? = nil,
        supportedReasoningLevels: [CodexReasoningEffortPreset],
        shellType: String,
        visibility: String,
        supportedInAPI: Bool,
        priority: Int,
        additionalSpeedTiers: [String],
        availabilityNUX: String? = nil,
        upgrade: String? = nil,
        baseInstructions: String,
        modelMessages: String? = nil,
        supportsReasoningSummaries: Bool,
        defaultReasoningSummary: String,
        supportVerbosity: Bool,
        defaultVerbosity: String? = nil,
        applyPatchToolType: String? = nil,
        webSearchToolType: String,
        truncationPolicy: CodexTruncationPolicy,
        supportsParallelToolCalls: Bool,
        supportsImageDetailOriginal: Bool,
        contextWindow: Int,
        maxContextWindow: Int,
        autoCompactTokenLimit: Int? = nil,
        effectiveContextWindowPercent: Int,
        experimentalSupportedTools: [String],
        inputModalities: [String],
        supportsSearchTool: Bool,
        multiAgentVersion: String? = nil,
        autoReviewModelOverride: String
    ) {
        self.slug = slug
        self.displayName = displayName
        self.description = description
        self.defaultReasoningLevel = defaultReasoningLevel
        self.supportedReasoningLevels = supportedReasoningLevels
        self.shellType = shellType
        self.visibility = visibility
        self.supportedInAPI = supportedInAPI
        self.priority = priority
        self.additionalSpeedTiers = additionalSpeedTiers
        self.availabilityNUX = availabilityNUX
        self.upgrade = upgrade
        self.baseInstructions = baseInstructions
        self.modelMessages = modelMessages
        self.supportsReasoningSummaries = supportsReasoningSummaries
        self.defaultReasoningSummary = defaultReasoningSummary
        self.supportVerbosity = supportVerbosity
        self.defaultVerbosity = defaultVerbosity
        self.applyPatchToolType = applyPatchToolType
        self.webSearchToolType = webSearchToolType
        self.truncationPolicy = truncationPolicy
        self.supportsParallelToolCalls = supportsParallelToolCalls
        self.supportsImageDetailOriginal = supportsImageDetailOriginal
        self.contextWindow = contextWindow
        self.maxContextWindow = maxContextWindow
        self.autoCompactTokenLimit = autoCompactTokenLimit
        self.effectiveContextWindowPercent = effectiveContextWindowPercent
        self.experimentalSupportedTools = experimentalSupportedTools
        self.inputModalities = inputModalities
        self.supportsSearchTool = supportsSearchTool
        self.multiAgentVersion = multiAgentVersion
        self.autoReviewModelOverride = autoReviewModelOverride
    }

}
