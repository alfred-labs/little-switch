import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Secret accounts")
struct SecretAccountTests {
    @Test("Accounts map to stable Keychain names")
    func keychainAccountNames() throws {
        let providerID = try #require(
            UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        )

        #expect(SecretAccount.provider(providerID).keychainAccount == providerID.uuidString)
        #expect(
            SecretAccount.script(providerID).keychainAccount == "script.\(providerID.uuidString)"
        )
        #expect(SecretAccount.webSearch(.firecrawl).keychainAccount == "web-search.firecrawl")
        #expect(SecretAccount.webSearch(.tavily).keychainAccount == "web-search.tavily")
        #expect(SecretAccount.webSearch(.brave).keychainAccount == "web-search.brave")
        #expect(SecretAccount.gatewayTLS.keychainAccount == "tls.gateway")
        #expect(SecretAccount.monitoring(providerID).keychainAccount == "monitoring.\(providerID.uuidString)")
    }

    @Test("Monitoring references remain isolated from all other secret accounts")
    func monitoringAccountIsolation() throws {
        let store = MemorySecretStore()
        let credentialID = UUID()
        let otherCredentialID = UUID()
        let accounts: [SecretAccount] = [
            .monitoring(credentialID),
            .monitoring(otherCredentialID),
            .provider(credentialID),
            .script(credentialID),
            .webSearch(.firecrawl),
            .webSearch(.tavily),
            .webSearch(.brave),
            .gatewayTLS,
        ]

        #expect(Set(accounts).count == accounts.count)
        #expect(Set(accounts.map(\.keychainAccount)).count == accounts.count)
        for (index, account) in accounts.enumerated() {
            try store.write("synthetic-\(index)", account: account)
        }
        try store.delete(account: .monitoring(credentialID))

        #expect(try store.read(account: .monitoring(credentialID)) == nil)
        for (index, account) in accounts.enumerated().dropFirst() {
            #expect(try store.read(account: account) == "synthetic-\(index)")
        }
    }
}
