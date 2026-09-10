import Foundation
import Security

public struct KeychainSecretStore: SecretStore {
    public enum Error: Swift.Error, Equatable {
        case status(OSStatus)
        case invalidValue
    }

    public let service: String

    public init(service: String = ProductIdentity.keychainService) {
        self.service = service
    }

    public func read(account: SecretAccount) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw Error.status(status)
        }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw Error.invalidValue
        }
        return value
    }

    public func write(_ secret: String, account: SecretAccount) throws {
        let data = Data(secret.utf8)
        if account == .gatewayTLS {
            // The gateway identity is machine-bound: never synced through
            // iCloud Keychain, present on this device only. Attributes
            // cannot change in place, so the item is re-added fresh.
            try? delete(account: account)
            var add = baseQuery(account: account)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw Error.status(addStatus)
            }
            return
        }
        let query = baseQuery(account: account)
        let status = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw Error.status(addStatus)
            }
            return
        }
        guard status == errSecSuccess else {
            throw Error.status(status)
        }
    }

    public func delete(account: SecretAccount) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Error.status(status)
        }
    }

    private func baseQuery(account: SecretAccount) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.keychainAccount,
        ]
        if account == .gatewayTLS {
            query[kSecAttrSynchronizable as String] = false
        }
        return query
    }
}
