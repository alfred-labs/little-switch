import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Responses wire override and probe persistence")
struct ResponsesWireOverridePersistenceTests {
    @Test(
        "A provider's responses wire override round-trips",
        arguments: [
            ProviderResponsesWireOverride.native,
            ProviderResponsesWireOverride.chatCompletions,
            nil,
        ])
    func overrideRoundTrip(
        responsesWireOverride: ProviderResponsesWireOverride?
    ) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = AppConfiguration(
            providers: [
                Provider(
                    name: "Routed",
                    baseURL: "https://example.com",
                    authMode: .bearer,
                    responsesWireOverride: responsesWireOverride
                )
            ]
        )
        let store = ConfigurationStore(
            fileURL: directory.appending(path: "config.json"),
            backupDirectory: directory.appending(path: "backups")
        )

        try store.save(configuration)
        #expect(try store.load() == configuration)
        #expect(
            try store.load().providers.first?.responsesWireOverride
                == responsesWireOverride
        )
    }

    @Test("The last wire probe round-trips with the provider")
    func wireProbeRoundTrip() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = ProviderWireProbe(
            messages: .available,
            responses: .absent,
            chatCompletions: .available,
            date: Date(timeIntervalSince1970: 100)
        )
        let configuration = AppConfiguration(
            providers: [
                Provider(
                    name: "Probed",
                    baseURL: "https://example.com",
                    authMode: .bearer,
                    wireProbe: probe
                )
            ]
        )
        let store = ConfigurationStore(
            fileURL: directory.appending(path: "config.json"),
            backupDirectory: directory.appending(path: "backups")
        )

        try store.save(configuration)
        #expect(try store.load().providers.first?.wireProbe == probe)
    }

    @Test("A legacy provider JSON without the new keys decodes as automatic")
    func legacyProviderDecodesAsAutomatic() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy =
            #"""
            {
              "version" : 7,
              "providers" : [
                {
                  "id" : "057265e6-9c83-4f9d-92a4-93986f1e30e5",
                  "name" : "Legacy",
                  "baseURL" : "https://example.com/api",
                  "authMode" : "bearer",
                  "models" : [],
                  "status" : "ready",
                  "maximumParallelRequests" : 4
                }
              ],
              "mappings" : {},
              "autoMode" : true,
              "connected" : false
            }
            """#
        let fileURL = directory.appending(path: "config.json")
        try Data(legacy.utf8).write(to: fileURL)
        let store = ConfigurationStore(
            fileURL: fileURL,
            backupDirectory: directory.appending(path: "backups")
        )

        let provider = try #require(try store.load().providers.first)
        #expect(provider.responsesWireOverride == nil)
        #expect(provider.wireProbe == nil)
    }

}

extension ResponsesWireOverridePersistenceTests {
    @Test("Pre-split z.ai configs decode as stored, without migration")
    func zaiLegacyConfigDecodesPlainly() throws {
        // A configuration written before split-surface support keeps its
        // stored base URL verbatim; no silent rewrite happens on load.
        let json = """
            {"version":7,"providers":[{"id":"\(UUID())","name":"z.ai",
            "baseURL":"https://api.z.ai/api/anthropic","authMode":"bearer",
            "credentialSource":"manual","models":[],"status":"idle",
            "maximumParallelRequests":2}],"mappings":{},"autoMode":false,
            "connected":false}
            """
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("config.json")
        try Data(json.utf8).write(to: fileURL)
        let store = ConfigurationStore(
            fileURL: fileURL,
            backupDirectory: directory.appendingPathComponent("backups")
        )
        let provider = try #require(try store.load().providers.first)
        #expect(provider.baseURL == "https://api.z.ai/api/anthropic")
        #expect(provider.anthropicBaseURL == nil)
    }
}
