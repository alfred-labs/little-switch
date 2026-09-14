import SwiftUI

enum ProviderEditorNotice {
    static var runningScript: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Testing the credential script; it may open a browser or prompt to log in.")
                .font(SettingsLayout.Typography.supporting)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    static func stageStatusRow(_ title: String, _ stage: ProviderTestStage) -> some View {
        HStack(alignment: .top, spacing: 6) {
            stageIcon(stage).frame(width: 14)
            VStack(alignment: .leading, spacing: 3) {
                if case .failed(let message) = stage {
                    Text(message)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .help(message)
                } else {
                    Text(title)
                }
            }
        }
        .font(SettingsLayout.Typography.supporting)
    }

    @ViewBuilder
    private static func stageIcon(_ stage: ProviderTestStage) -> some View {
        switch stage {
        case .idle:
            Image(systemName: "circle").foregroundStyle(.tertiary)
        case .passed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.orange)
        }
    }
}
