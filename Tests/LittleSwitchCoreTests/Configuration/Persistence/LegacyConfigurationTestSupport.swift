import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

/// Historical fixtures must contain the historical provider schema, even after the current encoder changes.
func configurationFixtureData(_ configuration: AppConfiguration) throws -> Data {
    let current = try JSONEncoder().encode(configuration)
    guard configuration.version <= 10 else { return current }
    var object = try #require(JSONSerialization.jsonObject(with: current) as? [String: Any])
    var rows = try #require(object["providers"] as? [[String: Any]])
    for (index, provider) in configuration.providers.enumerated() {
        if configuration.version == 10 {
            var credential: [String: Any] = ["authMode": provider.authMode.rawValue]
            if provider.credentialSource == .script {
                credential["path"] = provider.credentialScriptPath
                credential["refreshInterval"] = provider.credentialRefreshInterval
            }
            rows[index]["accounts"] = [
                [
                    "id": provider.id.uuidString, "name": "Primary", "isEnabled": true,
                    "credential": [provider.credentialSource.rawValue: credential],
                ]
            ]
            rows[index]["accountStrategy"] = "firstAvailable"
            for key in ["authMode", "credentialSource", "credentialScriptPath", "credentialRefreshInterval"] {
                rows[index].removeValue(forKey: key)
            }
        } else {
            rows[index].removeValue(forKey: "integration")
        }
    }
    object["providers"] = rows
    return try JSONSerialization.data(withJSONObject: object)
}
