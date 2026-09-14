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
        case .invalidInterval: "Choose an export interval between 5 and 300 seconds."
        case .invalidEndpoint(let signal):
            "Enter a complete HTTPS endpoint for \(signal.rawValue), or HTTP on this Mac."
        case .invalidToken(let signal): "The \(signal.rawValue) token contains invalid characters."
        case .missingToken(let signal): "Add a \(signal.rawValue) token or choose None for authentication."
        case .credentialWriteFailed: "The new monitoring token could not be saved in Keychain."
        case .saveFailed: "Monitoring settings could not be saved. The previous settings remain active."
        case .busy: "Monitoring settings are already being applied."
        }
    }
}
