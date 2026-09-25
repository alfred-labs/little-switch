import AppKit

/// Codex transaction actions dispatched from the status menu and settings.
extension LittleSwitchApplicationDelegate {
    func connectCodex() async {
        guard model.prepareDesktopConnection() else {
            showMainWindow()
            return
        }
        guard
            confirm(
                L10n.string(
                    "Connect Codex and ChatGPT to LittleSwitch? The desktop app will reopen once."
                )
            )
        else {
            return
        }
        await perform { try await $0.connectDesktopClients() }
    }

    func applyCodexSettings() async {
        await perform { try await $0.applyCodexSettings() }
    }

    func disconnectDesktopClients() async {
        guard
            confirmDiscardingPendingChanges(
                L10n.string(
                    "Disconnect Codex and ChatGPT from LittleSwitch? The desktop app will reopen with its normal connection."
                ),
                actionTitle: L10n.string("Disconnect")
            )
        else { return }
        await perform { try await $0.disconnectDesktopClients() }
    }
}
