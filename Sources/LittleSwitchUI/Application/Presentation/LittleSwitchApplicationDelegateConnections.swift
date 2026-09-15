import AppKit

/// Connection toggles driven from the status menu. Disconnecting throws away
/// any draft the application is holding, so each one asks with that named.
extension LittleSwitchApplicationDelegate {
    func toggleConnection() {
        guard let coordinator else {
            return
        }
        let disconnecting = model.connected
        let message =
            disconnecting
            ? L10n.string("Disconnect Claude from LittleSwitch? Claude will return to its first-party profile.")
            : L10n.string("Apply these LittleSwitch settings to Claude Desktop?")
        let confirmed =
            disconnecting
            ? confirmDiscardingPendingChanges(message, actionTitle: L10n.string("Disconnect"))
            : confirm(message)
        guard confirmed else {
            return
        }
        model.isBusy = true
        Task {
            do {
                let snapshot =
                    if disconnecting {
                        try await coordinator.disconnect()
                    } else {
                        try await coordinator.connect()
                    }
                model.apply(snapshot)
            } catch {
                present(error)
            }
        }
    }

    func toggleCodexConnection() {
        guard let coordinator else {
            return
        }
        let disconnecting = model.codexConnected
        let message =
            disconnecting
            ? L10n.string("Disconnect Codex from LittleSwitch? Codex will return to its previous configuration.")
            : L10n.string("Connect Codex to LittleSwitch with the exposed provider models?")
        let confirmed =
            disconnecting
            ? confirmDiscardingPendingChanges(message, actionTitle: L10n.string("Disconnect"))
            : confirm(message)
        guard confirmed else {
            return
        }
        model.isBusy = true
        Task {
            do {
                let snapshot =
                    if disconnecting {
                        try await coordinator.disconnectCodex()
                    } else {
                        try await coordinator.connectCodex()
                    }
                model.apply(snapshot)
            } catch {
                present(error)
            }
        }
    }

    /// A handoff is another instance taking over, not a user decision: asking
    /// there would block a replacement launch behind a dialog.
    func confirmQuitDiscardingPendingChanges() -> Bool {
        guard terminationState.mode == .userQuit,
            let warning = model.pendingChangesWarning
        else {
            return true
        }
        return confirm(
            L10n.string("\(warning) Quit LittleSwitch anyway?"),
            actionTitle: L10n.string("Quit")
        )
    }
}
