import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Memory secret service")
struct MemorySecretStoreTests {
    @Test("Memory secret store supports preserve, replace, and delete semantics")
    func memorySecrets() throws {
        let store = MemorySecretStore()
        let providerID = UUID()
        #expect(try store.read(providerID: providerID) == nil)
        try store.write("first", providerID: providerID)
        #expect(try store.read(providerID: providerID) == "first")
        try store.write("second", providerID: providerID)
        #expect(try store.read(providerID: providerID) == "second")
        try store.delete(providerID: providerID)
        #expect(try store.read(providerID: providerID) == nil)
    }
}
