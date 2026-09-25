import LittleSwitchCommon
import LittleSwitchCore

extension ApplicationCoordinator {
    public func setChatGPTModel(_ model: ModelMapping?) async throws -> CoordinatorSnapshot {
        try beginChatGPTOperation()
        if model != nil, ChatGPTConfiguration(model: model).resolvedModel(in: configuration.providers) == nil {
            throw Error.invalidMapping
        }
        pendingChatGPTSettings = model == configuration.chatgpt.model ? nil : ChatGPTSettingsDraft(model: model)
        return await snapshot()
    }

    public func applyChatGPTSettings() async throws -> CoordinatorSnapshot {
        try beginChatGPTOperation()
        guard hasPendingChatGPTChanges else { return await snapshot() }
        let candidate = applyingChatGPTDraft(to: configuration)
        guard candidate.chatgpt.resolvedModel(in: candidate.providers) != nil else {
            throw ChatGPTConnectionError.noModels
        }
        if configuration.chatgpt.connected { return try await connectChatGPT() }
        try configurationStore.save(candidate)
        configuration = candidate
        pendingChatGPTSettings = nil
        await replaceGatewayRoutingIfNeeded()
        return await snapshot()
    }

    var hasPendingChatGPTChanges: Bool {
        guard let pendingChatGPTSettings else { return false }
        return pendingChatGPTSettings.model != configuration.chatgpt.model
    }

    func applyingChatGPTDraft(to configuration: AppConfiguration) -> AppConfiguration {
        var candidate = configuration
        if let pendingChatGPTSettings { candidate.chatgpt.model = pendingChatGPTSettings.model }
        return candidate
    }
}
