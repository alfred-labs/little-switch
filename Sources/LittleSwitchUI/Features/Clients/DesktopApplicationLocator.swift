import Foundation
import LittleSwitchCommon

@MainActor
struct DesktopApplicationLocator {
    let homeDirectory: URL
    let runningApplication: (String) -> URL?
    let registeredApplication: (String) -> URL?
    let bundleIdentifier: (URL) -> String?

    func applicationURL(for application: DesktopApplication) -> URL? {
        let identifier = application.bundleIdentifier
        let candidates =
            [runningApplication(identifier), registeredApplication(identifier)].compactMap(\.self)
            + application.applicationCandidates(homeDirectory: homeDirectory)
        return candidates.first { bundleIdentifier($0) == identifier }
    }
}

extension DesktopApplication {
    var bundleIdentifier: String {
        switch self {
        case .claude: "com.anthropic.claudefordesktop"
        case .codex: "com.openai.codex"
        case .openCode: "ai.opencode.desktop"
        }
    }

    func applicationCandidates(homeDirectory: URL) -> [URL] {
        let names: [String] =
            switch self {
            case .claude: ["Claude.app"]
            case .codex: ["Codex.app", "ChatGPT.app"]
            case .openCode: ["OpenCode.app"]
            }
        let directories = [URL(filePath: "/Applications"), homeDirectory.appending(path: "Applications")]
        return directories.flatMap { directory in
            names.map { directory.appending(path: $0, directoryHint: .isDirectory) }
        }
    }
}
