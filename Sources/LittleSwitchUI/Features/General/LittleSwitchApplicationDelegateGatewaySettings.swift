import LittleSwitchCommon

extension LittleSwitchApplicationDelegate {
    func setAutoMode(_ enabled: Bool) async {
        await perform { try await $0.setAutoMode(enabled) }
    }

    func setModelIndicator(_ indicator: ModelIndicator) async {
        await perform { try await $0.setModelIndicator(indicator) }
    }
}
