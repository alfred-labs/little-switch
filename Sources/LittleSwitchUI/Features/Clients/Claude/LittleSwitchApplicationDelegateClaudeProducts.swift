extension LittleSwitchApplicationDelegate {
    func applyClaudeProducts(
        desktopAction: AppModel.ClaudePrimaryAction?,
        codeAction: AppModel.ClaudeCodePrimaryAction?
    ) async {
        let mappingsPending = model.hasPendingClaudeMappings
        guard mappingsPending || desktopAction != nil || codeAction != nil else {
            return
        }
        // A mapping-only apply is the lightweight remap commit — it asks no
        // more than the live edits it replaced did. The product actions keep
        // their confirm, since those touch profiles and relaunch apps.
        if desktopAction != nil || codeAction != nil {
            let targetNames = [
                desktopAction != nil ? "Claude Desktop" : nil,
                codeAction != nil ? "Claude Code" : nil,
            ].compactMap(\.self)
            guard
                confirm(
                    L10n.string(
                        "Apply these LittleSwitch settings to \(AppModel.list(targetNames))?"
                    )
                )
            else {
                return
            }
        }

        // The draft commits first, so product actions pick the new routing
        // up: a Claude Code connect normalizes against the fresh mappings.
        if mappingsPending {
            let committed = await perform { coordinator in
                try await coordinator.applyClaudeMappings()
            }
            guard committed else {
                return
            }
        }

        if let desktopAction {
            let succeeded = await perform { coordinator in
                switch desktopAction {
                case .connect:
                    try await coordinator.connect()
                }
            }
            guard succeeded else {
                return
            }
        }

        if let codeAction {
            await perform { coordinator in
                switch codeAction {
                case .connect:
                    return try await coordinator.connectClaudeCode()
                case .apply:
                    return try await coordinator.applyClaudeCode()
                case .restore:
                    _ = try await coordinator.restoreClaudeCodeSettings()
                    return try await coordinator.connectClaudeCode()
                }
            }
        }
    }
}
