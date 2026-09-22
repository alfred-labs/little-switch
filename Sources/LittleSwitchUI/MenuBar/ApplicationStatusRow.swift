import LittleSwitchCommon
import SwiftUI

struct ApplicationStatusRow: View {
    let name: String
    let icon: ApplicationStatusIcon
    let detail: String
    let connected: Bool
    let disabled: Bool
    var access: DesktopApplicationAccess = .available
    var launching = false
    var launchDisabled = false
    let onToggle: @MainActor () -> Void
    var onOpen: (@MainActor () -> Void)?

    private var available: Bool { access == .available }

    private var unavailableReason: String? {
        switch access {
        case .available: nil
        case .notInstalled: L10n.string("Application not installed")
        case .organizationManaged: L10n.string("Organization managed")
        }
    }

    var body: some View {
        HStack(spacing: StatusMenuLayout.contentSpacing) {
            applicationIcon
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: StatusMenuLayout.titleFontSize, weight: .medium))
                Text(unavailableReason ?? detail)
                    .font(.system(size: StatusMenuLayout.counterFontSize))
                    .foregroundStyle(.secondary)
            }
            .opacity(available ? 1 : 0.5)
            Spacer(minLength: 4)
            if access == .organizationManaged {
                Image(systemName: "lock")
                    .font(.system(size: StatusMenuLayout.counterFontSize))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            Toggle(
                L10n.resource("\(name) connection"),
                isOn: Binding(
                    get: { connected },
                    set: { _ in
                        guard available, !disabled else { return }
                        onToggle()
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(StatusMenuSwitchStyle())
            .controlSize(.mini)
            .disabled(disabled || !available)
            .accessibilityHint(unavailableReason ?? detail)
        }
        .saturation(available ? 1 : 0)
        .padding(.leading, StatusMenuLayout.horizontalPadding - 4)
        .padding(.trailing, StatusMenuLayout.horizontalPadding)
        .frame(width: StatusMenuLayout.width, height: StatusMenuLayout.applicationRowHeight)
        .help(unavailableReason ?? detail)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var applicationIcon: some View {
        if let onOpen {
            Button {
                guard available, !launchDisabled, !launching else { return }
                onOpen()
            } label: {
                mark
            }
            .buttonStyle(.borderless)
            .disabled(!available || launchDisabled || launching)
            .accessibilityLabel(L10n.resource("Open \(name)"))
            .accessibilityHint(unavailableReason ?? L10n.string("Opens the app without changing its connection"))
            .help(unavailableReason ?? L10n.string("Open \(name)"))
        } else {
            mark
        }
    }

    private var mark: some View {
        icon.mark
            .frame(width: StatusMenuLayout.iconSize, height: StatusMenuLayout.iconSize)
            .frame(width: StatusMenuLayout.launchTargetSize, height: StatusMenuLayout.launchTargetSize)
            .contentShape(.rect)
            .opacity(available ? 1 : 0.45)
            .accessibilityHidden(true)
    }
}
