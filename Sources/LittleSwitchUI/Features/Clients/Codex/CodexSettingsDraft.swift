import LittleSwitchCore

public struct CodexSettingsDraft: Equatable, Sendable {
    public var defaultModel: ModelMapping?
    public var excludedModels: [ModelMapping]
    public var autoReviewModel: ModelMapping?

    public init(
        defaultModel: ModelMapping?,
        excludedModels: [ModelMapping],
        autoReviewModel: ModelMapping? = nil
    ) {
        self.defaultModel = defaultModel
        self.excludedModels = excludedModels
        self.autoReviewModel = autoReviewModel
    }

    public init(configuration: AppConfiguration) {
        self.init(
            defaultModel: configuration.codex.defaultModel,
            excludedModels: configuration.codex.excludedModels,
            autoReviewModel: configuration.codex.autoReviewModel
        )
    }

    public func applying(to configuration: AppConfiguration) -> AppConfiguration {
        var result = configuration
        result.codex.defaultModel = defaultModel
        result.codex.excludedModels = excludedModels
        result.codex.autoReviewModel = autoReviewModel
        result.codex = result.codex.normalized(for: result.providers)
        return result
    }

    public func reconciled(providers: [Provider]) -> CodexSettingsDraft {
        var configuration = CodexConfiguration(
            defaultModel: defaultModel,
            excludedModels: excludedModels,
            autoReviewModel: autoReviewModel
        )
        configuration = configuration.normalized(for: providers)
        return CodexSettingsDraft(
            defaultModel: configuration.defaultModel,
            excludedModels: configuration.excludedModels,
            autoReviewModel: configuration.autoReviewModel
        )
    }
}
