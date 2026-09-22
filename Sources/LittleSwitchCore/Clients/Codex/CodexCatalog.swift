import Foundation
import LittleSwitchCommon

extension String {
    /// Case-insensitive slug identity shared by managed and native entries.
    fileprivate var trimmedSlugKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public enum CodexCatalog {
    public enum Error: Swift.Error, Equatable {
        case empty
        case unavailableAutoReviewModel
        case ambiguousModelIdentifiers
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

    /// Preserve case-sensitive model identity in a namespace that cannot
    /// capture an existing provider/model alias. Display names stay readable.
    package static func slug(for target: CodexModelTarget) -> String {
        ManagedModelIdentifier.make(providerName: target.provider.name, modelID: target.model.id)
    }

    package static func make(
        providers: [Provider],
        configuration: CodexConfiguration,
        responsesWireVerdicts: [UUID: Bool] = [:]
    ) throws -> CodexModelCatalog {
        var targets = configuration.exposedModels(in: providers)
        guard !targets.isEmpty else {
            throw Error.empty
        }
        guard Set(targets.map { slug(for: $0) }).count == targets.count else {
            throw Error.ambiguousModelIdentifiers
        }
        if let defaultModel = configuration.resolvedDefaultModel(in: providers) {
            if let index = targets.firstIndex(where: { $0.mapping == defaultModel }) {
                targets.insert(targets.remove(at: index), at: 0)
            }
        }
        var models = try targets.enumerated().map { index, target in
            try makeModel(target: target, priority: index, learnedNative: responsesWireVerdicts[target.provider.id])
        }
        guard let reviewerTarget = configuration.resolvedAutoReviewTarget(in: providers) else {
            throw Error.unavailableAutoReviewModel
        }
        // Codex selects the reviewer separately from the task. Its hidden entry
        // carries the actual review model's capabilities and identity so profile
        // signatures also detect reviewer changes between equal-capacity models.
        var reviewer = try makeModel(
            target: reviewerTarget,
            priority: models.count,
            learnedNative: responsesWireVerdicts[reviewerTarget.provider.id])
        reviewer.slug = managedAutoReviewModel
        reviewer.displayName = managedAutoReviewModel
        reviewer.description = "Approval reviews via \(reviewerTarget.displayName)"
        reviewer.visibility = "hide"
        models.append(reviewer)
        return CodexModelCatalog(models: models)
    }

    package static func encode(
        providers: [Provider],
        configuration: CodexConfiguration,
        responsesWireVerdicts: [UUID: Bool] = [:]
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(
            make(
                providers: providers, configuration: configuration, responsesWireVerdicts: responsesWireVerdicts))
        data.append(UInt8(ascii: "\n"))
        return data
    }

    /// Encodes the managed catalog merged with Codex's native entries. The
    /// LittleSwitch entries win slug collisions and keep their API support;
    /// native entries are marked ChatGPT-only and preserved field-for-field.
    package static func encode(
        providers: [Provider],
        configuration: CodexConfiguration,
        nativeCatalogData: Data?,
        responsesWireVerdicts: [UUID: Bool] = [:]
    ) throws -> Data {
        try mergedData(
            managedData: encode(
                providers: providers, configuration: configuration, responsesWireVerdicts: responsesWireVerdicts),
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
        priority: Int,
        learnedNative: Bool?
    ) throws -> CodexCatalogModel {
        let contextWindow = target.model.effectiveContextWindow ?? 128_000
        let acceptsImages = try ModelImageInputPolicyResolver.acceptsImages(
            provider: target.provider,
            model: target.model,
            wire: ProviderResponsesWireResolver.resolve(provider: target.provider, learnedNative: learnedNative),
            observations: target.provider.imageInputObservations)
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
            inputModalities: acceptsImages
                ? ["text", "image"]
                : ["text"],
            supportsSearchTool: false,
            multiAgentVersion: "v2",
            autoReviewModelOverride: managedAutoReviewModel
        )
    }
}
