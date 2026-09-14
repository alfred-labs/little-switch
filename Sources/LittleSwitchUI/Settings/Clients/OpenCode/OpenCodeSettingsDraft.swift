import LittleSwitchCommon
import LittleSwitchCore

public struct OpenCodeSettingsDraft: Equatable, Sendable {
    public var defaultModel: ModelMapping?

    public init(defaultModel: ModelMapping?) {
        self.defaultModel = defaultModel
    }

    public init(configuration: AppConfiguration) {
        defaultModel = configuration.openCode.defaultModel
    }

    public func applying(to configuration: AppConfiguration) -> AppConfiguration {
        var result = configuration
        result.openCode.defaultModel = defaultModel
        result.openCode = result.openCode.normalized(
            providers: result.providers,
            codex: result.codex
        )
        return result
    }

    public func reconciled(with configuration: AppConfiguration) -> OpenCodeSettingsDraft {
        OpenCodeSettingsDraft(configuration: applying(to: configuration))
    }
}
