import Foundation
import LittleSwitchCommon

enum DesktopApplicationLaunchError: Swift.Error, Equatable, LocalizedError {
    case notInstalled(DesktopApplication)
    case organizationManaged
    case launchFailed(DesktopApplication)

    var errorDescription: String? {
        switch self {
        case .notInstalled(let application):
            L10n.string("\(application.displayName) is not installed.")
        case .organizationManaged:
            L10n.string("Your organization manages Claude Desktop. LittleSwitch cannot open or connect it.")
        case .launchFailed(let application):
            L10n.string("Could not open \(application.displayName). Try opening it from Finder.")
        }
    }
}

extension DesktopApplication {
    var displayName: String {
        switch self {
        case .claude: L10n.string("Claude Desktop")
        case .codex: L10n.string("Codex")
        case .openCode: L10n.string("OpenCode")
        }
    }
}
