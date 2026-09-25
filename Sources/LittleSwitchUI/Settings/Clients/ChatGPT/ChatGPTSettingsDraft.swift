import LittleSwitchCommon

package struct ChatGPTSettingsDraft: Equatable, Sendable {
    package var model: ModelMapping?

    package init(model: ModelMapping?) {
        self.model = model
    }
}
