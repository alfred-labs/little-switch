import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Credential source persistence migration")
struct CredentialSourcePersistenceTests {
    private func makeStore() throws -> (ConfigurationStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ConfigurationStore(
            fileURL: directory.appending(path: "config.json"),
            backupDirectory: directory.appending(path: "backups")
        )
        return (store, directory)
    }

    private func loadProviderRow(_ rawJSON: String, store: ConfigurationStore) throws -> Provider {
        let data = try JSONSerialization.data(
            withJSONObject: try #require(
                JSONSerialization.jsonObject(with: Data(rawJSON.utf8)) as? [String: Any]
            )
        )
        try data.write(to: store.fileURL)
        let configuration = try store.load()
        return try #require(configuration.providers.first)
    }

    @Test("A pre-split script provider decodes as Bearer with a script source")
    func legacyScriptAuthModeDecodes() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let row = try loadProviderRow(
            """
            {
                "version": 7,
                "providers": [
                    {
                        "id": "69B41598-0E7C-4D28-9C11-3B04D6C0A111",
                        "name": "vault",
                        "baseURL": "https://vault.example.com",
                        "authMode": "script",
                        "credentialScriptPath": "/usr/local/bin/token.sh",
                        "models": [],
                        "status": "ready",
                        "maximumParallelRequests": 4
                    }
                ],
                "mappings": {},
                "autoMode": true,
                "connected": false
            }
            """,
            store: store
        )

        #expect(row.authMode == .bearer)
        #expect(row.credentialSource == .script)
        #expect(row.credentialScriptPath == "/usr/local/bin/token.sh")
    }

    @Test("A pre-merge optional-bearer provider decodes as Bearer with manual source")
    func legacyOptionalBearerDecodesToManualSource() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let row = try loadProviderRow(
            """
            {
                "version": 7,
                "providers": [
                    {
                        "id": "69B41598-0E7C-4D28-9C11-3B04D6C0A112",
                        "name": "local",
                        "baseURL": "http://127.0.0.1:11434",
                        "authMode": "optional-bearer",
                        "models": [],
                        "status": "ready",
                        "maximumParallelRequests": 4
                    }
                ],
                "mappings": {},
                "autoMode": true,
                "connected": false
            }
            """,
            store: store
        )

        #expect(row.authMode == .bearer)
        #expect(row.credentialSource == .manual)
        #expect(row.credentialScriptPath == nil)
    }

    @Test("An explicit credential source wins over the legacy default")
    func explicitCredentialSourceIsKept() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let row = try loadProviderRow(
            """
            {
                "version": 7,
                "providers": [
                    {
                        "id": "69B41598-0E7C-4D28-9C11-3B04D6C0A113",
                        "name": "keyed",
                        "baseURL": "https://api.example.com",
                        "authMode": "x-api-key",
                        "credentialSource": "script",
                        "models": [],
                        "status": "ready",
                        "maximumParallelRequests": 4
                    }
                ],
                "mappings": {},
                "autoMode": true,
                "connected": false
            }
            """,
            store: store
        )

        #expect(row.authMode == .xAPIKey)
        #expect(row.credentialSource == .script)
    }

    @Test("An unknown stored auth mode fails the decode")
    func unknownAuthModeIsRejected() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rawJSON = """
            {
                "version": 7,
                "providers": [
                    {
                        "id": "69B41598-0E7C-4D28-9C11-3B04D6C0A114",
                        "name": "odd",
                        "baseURL": "https://api.example.com",
                        "authMode": "kerberos",
                        "models": [],
                        "status": "ready",
                        "maximumParallelRequests": 4
                    }
                ],
                "mappings": {},
                "autoMode": true,
                "connected": false
            }
            """
        let data = try JSONSerialization.data(
            withJSONObject: try #require(
                JSONSerialization.jsonObject(with: Data(rawJSON.utf8)) as? [String: Any]
            )
        )
        try data.write(to: store.fileURL)

        #expect(throws: (any Error).self) { try store.load() }
    }
}
