import Foundation
import LittleSwitchCommon

/// Decode-only boundary for the experimental version 10 account schema.
/// Only the original primary identity can reuse the provider's Keychain entry.
enum ExperimentalProviderConfiguration {
    private enum CodingKeys: String, CodingKey { case id, accounts }

    private struct Account: Decodable {
        let id: UUID
        let isEnabled: Bool
        let credential: Credential
    }

    private enum Credential: Decodable {
        case manual(authMode: AuthMode)
        case script(authMode: AuthMode, path: String?, refreshInterval: TimeInterval?)
    }

    static func decode(from decoder: Decoder) throws -> Provider {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let id = try values.decode(UUID.self, forKey: .id)
        let accounts = try values.decode([Account].self, forKey: .accounts)
        guard accounts.count == 1, let primary = accounts.first, primary.id == id, primary.isEnabled else {
            throw DecodingError.dataCorruptedError(
                forKey: .accounts,
                in: values,
                debugDescription: "Only one enabled primary account can migrate to provider-owned credentials")
        }
        let credentials: LegacyProviderConfiguration.Credentials
        switch primary.credential {
        case .manual(let authMode):
            credentials = .init(authMode: authMode, source: .manual, scriptPath: nil, refreshInterval: nil)
        // swift-format keeps bindings inside enum payloads.
        // swiftlint:disable:next pattern_matching_keywords
        case .script(let authMode, let path, let interval):
            guard authMode != .none else {
                throw DecodingError.dataCorruptedError(
                    forKey: .accounts, in: values, debugDescription: "Script credentials require authentication")
            }
            credentials = .init(authMode: authMode, source: .script, scriptPath: path, refreshInterval: interval)
        }
        return try LegacyProviderConfiguration.decode(from: decoder, configurationVersion: 10, credentials: credentials)
    }
}
