import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Search secret account separation")
struct SearchSecretAccountTests {
    @Test("Provider and Firecrawl credentials use distinct stable accounts")
    func secretAccounts() throws {
        let store = MemorySecretStore()
        let providerID = UUID()
        try store.write("provider", account: .provider(providerID))
        try store.write("search", account: .webSearch(.firecrawl))
        #expect(try store.read(providerID: providerID) == "provider")
        #expect(try store.read(account: .webSearch(.firecrawl)) == "search")
        try store.delete(account: .webSearch(.firecrawl))
        #expect(try store.read(providerID: providerID) == "provider")
    }
}
