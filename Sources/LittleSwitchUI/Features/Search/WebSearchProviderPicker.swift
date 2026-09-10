import LittleSwitchSearch
import SwiftUI

struct WebSearchProviderPicker: View {
    @Binding var selection: WebSearchProvider
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.layoutDirection) private var layoutDirection
    @FocusState private var focusedProvider: WebSearchProvider?

    var body: some View {
        HStack(alignment: .top, spacing: SettingsLayout.SearchProvider.choiceSpacing) {
            ForEach(WebSearchProvider.allCases, id: \.self) { provider in
                Button {
                    guard isEnabled else { return }
                    selection = provider
                } label: {
                    choice(provider)
                }
                .buttonStyle(.plain)
                .focused($focusedProvider, equals: provider)
                .accessibilityLabel(provider.settingsTitle)
                .accessibilityAddTraits(selection == provider ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SettingsLayout.SearchProvider.verticalInset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search provider")
        .onMoveCommand(perform: moveSelection)
    }

    private func choice(_ provider: WebSearchProvider) -> some View {
        let selected = selection == provider
        return VStack(spacing: SettingsLayout.SearchProvider.labelSpacing) {
            provider.settingsLogo
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: SettingsLayout.SearchProvider.logoSize, height: SettingsLayout.SearchProvider.logoSize)
                .frame(width: SettingsLayout.SearchProvider.tileSize, height: SettingsLayout.SearchProvider.tileSize)
                .background(
                    selected ? Color.accentColor : Color.primary.opacity(0.055),
                    in: .rect(cornerRadius: SettingsLayout.SearchProvider.cornerRadius)
                )
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(SettingsLayout.Typography.selectionCheckmark)
                            .foregroundStyle(.white)
                            .padding(SettingsLayout.SearchProvider.checkmarkInset)
                            .accessibilityHidden(true)
                    }
                }
            Text(provider.settingsTitle)
                .font(SettingsLayout.Typography.rowLabel)
                .foregroundStyle(selected ? Color.primary : Color.secondary)
        }
        .frame(width: SettingsLayout.SearchProvider.choiceWidth)
        .contentShape(Rectangle())
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard isEnabled else { return }
        let offset: Int
        switch direction {
        case .left: offset = layoutDirection == .leftToRight ? -1 : 1
        case .right: offset = layoutDirection == .leftToRight ? 1 : -1
        default: return
        }
        let providers = WebSearchProvider.allCases
        guard let focused = focusedProvider,
            let current = providers.firstIndex(of: focused),
            providers.indices.contains(current + offset)
        else { return }
        selection = providers[current + offset]
        focusedProvider = selection
    }
}

@MainActor
extension WebSearchProvider {
    fileprivate var settingsTitle: String {
        switch self {
        case .disabled: "None"
        case .firecrawl: "Firecrawl"
        case .tavily: "Tavily"
        case .brave: "Brave"
        case .exa: "Exa"
        }
    }

    fileprivate var settingsLogo: some View {
        Group {
            switch self {
            case .disabled:
                Image(systemName: "nosign")
                    .resizable()
                    .scaledToFit()
                    .padding(3)
            case .firecrawl: FirecrawlIcon()
            case .tavily: TavilyIcon()
            case .brave: BraveIcon()
            case .exa: ExaIcon()
            }
        }
        .accessibilityHidden(true)
    }
}
