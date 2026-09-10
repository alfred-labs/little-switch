import LittleSwitchCore
import SwiftUI

struct ProviderSettingsRow: View {
    let provider: Provider
    let scriptFailure: String?

    var body: some View {
        HStack(spacing: 12) {
            ProviderIdentityIcon(baseURL: provider.baseURL)
                .frame(width: 22, height: 22)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(provider.name)
                    .font(.body.weight(.medium))
                Text(provider.baseURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(provider.baseURL)
                if provider.credentialSource == .script, let scriptFailure {
                    Label(scriptFailure, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .help(scriptFailure)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Label(statusTitle, systemImage: statusSymbol)
                .font(.caption)
                .foregroundStyle(statusColor)
                .frame(width: 92, alignment: .leading)
            Text("\(provider.models.count) models")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var statusTitle: String {
        switch provider.status {
        case .ready: "Ready"
        case .refreshing: "Refreshing"
        case .unavailable: "Unavailable"
        case .idle: "Not tested"
        }
    }

    private var statusSymbol: String {
        switch provider.status {
        case .ready: "checkmark.circle"
        case .refreshing: "arrow.triangle.2.circlepath"
        case .unavailable: "exclamationmark.triangle"
        case .idle: "circle.dashed"
        }
    }

    private var statusColor: Color {
        switch provider.status {
        case .ready: .green
        case .refreshing: .secondary
        case .unavailable: .orange
        case .idle: .secondary
        }
    }
}

private struct ProviderIdentityIcon: View {
    let baseURL: String

    var body: some View {
        let url = URL(string: baseURL)
        let host = url?.host?.lowercased()
        if host == "api.z.ai" || host == "open.bigmodel.cn" {
            ZaiIcon()
        } else if ["localhost", "127.0.0.1", "[::1]"].contains(host), url?.port == 11_434 {
            OllamaIcon()
        } else {
            Image(systemName: "server.rack")
                .font(.system(size: 19))
        }
    }
}
