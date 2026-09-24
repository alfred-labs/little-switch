import Foundation

extension AppModel.Section {
    var title: String {
        switch self {
        case .common: L10n.string("General")
        case .providers: L10n.string("Providers")
        case .webSearch: L10n.string("Web Search")
        case .monitoring: L10n.string("Monitoring")
        case .claude: L10n.string("Claude")
        case .codex: L10n.string("Codex")
        case .chatGPT: L10n.string("ChatGPT")
        case .openCode: L10n.string("OpenCode")
        }
    }
}

extension AppModel.SidebarGroup {
    var title: String {
        switch self {
        case .common: L10n.string("Common")
        case .backends: L10n.string("Backends")
        case .apps: L10n.string("Apps")
        }
    }
}
