import LittleSwitchCore
import SwiftUI

struct ClaudeCodeSettingsView: View {
    @Bindable var model: AppModel
    let onDefault: @MainActor (String?, ClaudeCodeContextMode) async -> Void

    var body: some View {
        SettingsSection("Terminal") {
            SettingsCard {
                LabeledContent("Default model") {
                    defaultModelPicker
                }
                .settingsRow()
            }
            VStack(alignment: .leading, spacing: 6) {
                statusNotice
                if model.claudeCodeMappedRouteOptions.isEmpty {
                    Label(
                        "Map at least one Claude route before connecting Claude Code.",
                        systemImage: "info.circle"
                    )
                }
                Text("Applies to new terminal sessions.")
            }
            .settingsSupportingText()
        }
    }

    private var defaultModelPicker: some View {
        Picker(
            "Default model",
            selection: Binding<ClaudeCodeDefaultModelOption?>(
                get: { model.claudeCodeDefaultModelSelection },
                set: { option in
                    guard let option else {
                        return
                    }
                    Task {
                        await onDefault(option.routeID, option.contextMode)
                    }
                }
            )
        ) {
            ForEach(model.claudeCodeDefaultModelOptions) { option in
                Text(option.label).tag(Optional(option))
            }
        }
        .labelsHidden()
        .settingsMenuPicker(width: SettingsLayout.mappingControlWidth)
        .disabled(model.isBusy || model.claudeCodeDefaultModelOptions.isEmpty)
    }

    @ViewBuilder
    private var statusNotice: some View {
        switch model.claudeCodeStatus {
        case .disconnected:
            EmptyView()
        case .connected:
            EmptyView()
        case .needsAttention:
            EmptyView()
        case .recoveryAvailable:
            notice(
                "Previous user-level settings can be restored.",
                systemImage: "clock.arrow.circlepath"
            )
        case .recoveryUnavailable:
            notice(
                "Recovery data is unavailable.",
                systemImage: "exclamationmark.octagon"
            )
        }
    }

    private func notice(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .settingsSupportingText()
    }

}
