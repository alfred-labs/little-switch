import AppKit

/// Codex transaction actions dispatched from the status menu and settings.
extension LittleSwitchApplicationDelegate {
    func connectCodex() async {
        guard
            confirm(
                "Connect Codex to LittleSwitch with the exposed provider models?"
            )
        else {
            return
        }
        await perform { try await $0.connectCodex() }
    }

    func applyCodexSettings() async {
        await perform { try await $0.applyCodexSettings() }
    }
}
