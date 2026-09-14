import LittleSwitchCommon
import LittleSwitchCore

extension LittleSwitchApplicationDelegate {
    func toggleOpenCodeConnection(restoring: Bool) {
        if restoring {
            Task { await restoreOpenCodeSettings() }
        } else {
            Task { await connectOpenCode() }
        }
    }

    func setOpenCodeDefault(_ mapping: ModelMapping?) async {
        await perform { try await $0.setOpenCodeDefaultModel(mapping) }
    }

    func connectOpenCode() async {
        await perform { try await $0.connectOpenCode() }
    }

    func applyOpenCodeSettings() async {
        await perform { try await $0.applyOpenCode() }
    }

    func restoreOpenCodeSettings() async {
        guard
            confirmDiscardingPendingChanges(
                "Restore the previous user-level OpenCode settings?",
                actionTitle: "Restore"
            )
        else {
            return
        }
        await perform { try await $0.restoreOpenCodeSettings() }
    }
}
