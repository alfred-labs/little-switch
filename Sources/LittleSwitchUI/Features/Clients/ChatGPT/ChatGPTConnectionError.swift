import Foundation

enum ChatGPTConnectionError: LocalizedError {
    case unavailable
    case noModels
    case pendingCodex
    case trustRequired
    case operationInProgress
    case rollbackFailed
    case conflictingEnvironment

    var errorDescription: String? {
        switch self {
        case .unavailable: L10n.string("ChatGPT could not be opened. Install the desktop app and try again.")
        case .noModels: L10n.string("Enable a model in Codex before connecting ChatGPT.")
        case .pendingCodex: L10n.string("Apply Codex changes before opening ChatGPT.")
        case .trustRequired: L10n.string("Approve the local certificate to connect ChatGPT securely.")
        case .operationInProgress: L10n.string("Wait for the current desktop operation to finish.")
        case .rollbackFailed:
            L10n.string("ChatGPT could not be restored. Keep LittleSwitch open and try Disconnect again.")
        case .conflictingEnvironment:
            L10n.string(
                "ChatGPT already has a different launch connection. Open LittleSwitch without that override and try again."
            )
        }
    }
}
