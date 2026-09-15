import Foundation
import LittleSwitchCommon
import LittleSwitchCore

enum MonitoringSettingsError: LocalizedError, Equatable, Sendable {
    case invalidInterval
    case invalidEndpoint(MonitoringSignal)
    case invalidToken(MonitoringSignal)
    case missingToken(MonitoringSignal)
    case credentialWriteFailed
    case saveFailed
    case busy

    var errorDescription: String? {
        switch self {
        case .invalidInterval: L10n.string("Choose an export interval between 5 and 300 seconds.")
        case .invalidEndpoint(let signal):
            L10n.string("Enter a complete HTTPS endpoint for \(signal.rawValue), or HTTP on this Mac.")
        case .invalidToken(let signal):
            L10n.string("The \(signal.rawValue) token contains invalid characters.")
        case .missingToken(let signal):
            L10n.string("Add a \(signal.rawValue) token or choose None for authentication.")
        case .credentialWriteFailed: L10n.string("The new monitoring token could not be saved in Keychain.")
        case .saveFailed:
            L10n.string("Monitoring settings could not be saved. The previous settings remain active.")
        case .busy: L10n.string("Monitoring settings are already being applied.")
        }
    }
}
