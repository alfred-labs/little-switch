import Foundation

enum ChatGPTConnectionError: LocalizedError {
    case unavailable
    case noModels
    case trustRequired
    case certificateBundleUnavailable
    case operationInProgress
    case rollbackFailed
    case conflictingEnvironment
    case settingsChanged

    var errorDescription: String? {
        switch self {
        case .unavailable: L10n.string("ChatGPT could not be opened. Install the desktop app and try again.")
        case .noModels: L10n.string("Choose an available model for Chat before connecting.")
        case .trustRequired: L10n.string("Approve the local certificate to connect ChatGPT securely.")
        case .certificateBundleUnavailable:
            L10n.string("ChatGPT certificates could not be prepared. Check your certificate settings and try again.")
        case .operationInProgress: L10n.string("Wait for the current desktop operation to finish.")
        case .settingsChanged: L10n.string("Settings changed while the desktop app was reopening. Try again.")
        case .rollbackFailed:
            L10n.string("ChatGPT could not be restored. Keep LittleSwitch open and try Disconnect again.")
        case .conflictingEnvironment:
            L10n.string(
                "ChatGPT already has a different launch connection. Open LittleSwitch without that override and try again."
            )
        }
    }
}
