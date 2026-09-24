import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

struct ChatGPTLaunchEnvironmentTests {
    @Test func redirectsOnlyTheDesktopAndAppServerBackends() throws {
        let original = ["PATH": "/usr/bin", "CUSTOM_SETTING": "kept"]
        #expect(
            try ChatGPTLaunchEnvironment.connected(inheriting: original) == [
                "PATH": "/usr/bin", "CUSTOM_SETTING": "kept",
                "CODEX_API_BASE_URL": "https://localhost:8000/backend-api",
                "CODEX_APP_SERVER_CHATGPT_BASE_URL": "https://localhost:8000/backend-api",
            ])
        #expect(original == ["PATH": "/usr/bin", "CUSTOM_SETTING": "kept"])
    }

    @Test(arguments: ["CODEX_API_BASE_URL", "CODEX_APP_SERVER_CHATGPT_BASE_URL"])
    func rejectsAnExistingDifferentBackend(key: String) {
        #expect(throws: ChatGPTLaunchEnvironment.Error.conflictingBackend) {
            try ChatGPTLaunchEnvironment.connected(inheriting: [key: "https://example.invalid/backend-api"])
        }
    }

    @Test func acceptsAnAlreadyConnectedEnvironmentAndEmptyOverrides() throws {
        let connected = try ChatGPTLaunchEnvironment.connected(inheriting: [:])
        #expect(try ChatGPTLaunchEnvironment.connected(inheriting: connected) == connected)
        #expect(try ChatGPTLaunchEnvironment.connected(inheriting: ["CODEX_API_BASE_URL": "  "]) == connected)
    }

    @Test func decodesOldConfigurationsDisconnectedAndRoundTripsConnection() throws {
        let old = Data(
            #"{"version":9,"providers":[],"mappings":{},"autoMode":true,"connected":false}"#.utf8)
        let configuration = try JSONDecoder().decode(AppConfiguration.self, from: old)
        #expect(configuration.chatgpt == .disconnected)
        var connected = configuration
        connected.chatgpt = ChatGPTConfiguration(connected: true)
        let encoded = try JSONEncoder().encode(connected)
        #expect(try JSONDecoder().decode(AppConfiguration.self, from: encoded) == connected)
    }
}
