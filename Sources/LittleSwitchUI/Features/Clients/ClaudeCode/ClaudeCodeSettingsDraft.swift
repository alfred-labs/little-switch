import LittleSwitchCore

public struct ClaudeCodeSettingsDraft: Equatable, Sendable {
    public var defaultModel: String?
    public var contextMode: ClaudeCodeContextMode

    public init(
        defaultModel: String?,
        contextMode: ClaudeCodeContextMode = .standard
    ) {
        self.defaultModel = defaultModel
        self.contextMode = contextMode
    }

    public init(configuration: AppConfiguration) {
        defaultModel = configuration.claudeCode.defaultModel
        contextMode = configuration.claudeCode.contextMode
    }

    public func applying(to configuration: AppConfiguration) -> AppConfiguration {
        var result = configuration
        result.claudeCode.defaultModel = defaultModel
        result.claudeCode.contextMode = contextMode
        result.claudeCode = result.claudeCode.normalized(
            providers: result.providers,
            mappings: result.mappings
        )
        return result
    }

    public func reconciled(
        with configuration: AppConfiguration
    ) -> ClaudeCodeSettingsDraft {
        ClaudeCodeSettingsDraft(
            configuration: applying(to: configuration)
        )
    }
}
