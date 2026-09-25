import Foundation
import LittleSwitchCore
import NIOSSL
import Testing

@testable import LittleSwitchUI

@MainActor
struct ChatGPTLaunchTrustTests {
    @Test("The desktop receives a readable CA bundle before account discovery starts")
    func providesAppServerTrust() async throws {
        let fixture = try await ChatGPTFixture.make()
        let authorityPEM = fixture.authorityPEM
        fixture.controller.onOpen = { environment in
            guard environment["CODEX_API_BASE_URL"] != nil else { return }
            #expect(environment["CODEX_CA_CERTIFICATE"] != nil)
            guard let path = environment["CODEX_CA_CERTIFICATE"] else { return }
            do {
                let certificates = try NIOSSLCertificate.fromPEMFile(path)
                #expect(certificates == (try NIOSSLCertificate.fromPEMBytes(Array(authorityPEM.utf8))))
            } catch { Issue.record(error) }
        }
        _ = try await fixture.coordinator.connectChatGPT()
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Codex cannot quit the desktop when ChatGPT recovery could not prepare trust")
    func recoveryFailurePreventsCodexQuit() async throws {
        let missing = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let fixture = try await ChatGPTFixture.make(
            connected: true, environment: ["CODEX_CA_CERTIFICATE": missing.path])
        #expect(await fixture.coordinator.snapshot().chatGPTStatus == .needsAttention)
        await #expect(throws: ChatGPTConnectionError.certificateBundleUnavailable) {
            try await fixture.coordinator.connectCodex()
        }
        #expect(!fixture.events.recorded.contains("quit"))
        #expect(fixture.controller.running)
        #expect(!fixture.store.configuration.codex.connected)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Every shared desktop relaunch validates inherited trust before quitting", arguments: ["chatgpt", "codex"])
    func revalidatesInheritedTrust(client: String) async throws {
        let sourceDirectory = ChatGPTTestCertificateDirectory()
        try FileManager.default.createDirectory(at: sourceDirectory.url, withIntermediateDirectories: true)
        let source = sourceDirectory.url.appending(path: "custom.pem")
        let fixture = try await ChatGPTFixture.make(environment: ["CODEX_CA_CERTIFICATE": source.path])
        try Data(fixture.authorityPEM.utf8).write(to: source)
        _ = try await fixture.coordinator.connectChatGPT()
        let before = fixture.events.recorded
        try Data("invalid".utf8).write(to: source)
        await #expect(throws: ChatGPTConnectionError.certificateBundleUnavailable) {
            if client == "chatgpt" { return try await fixture.coordinator.connectChatGPT() }
            return try await fixture.coordinator.connectCodex()
        }
        #expect(!fixture.events.recorded.dropFirst(before.count).contains("quit"))
        #expect(fixture.controller.running)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Managed relaunch and rollback retain the bundle, while disconnect restores inherited trust")
    func launchRestoration() async throws {
        let sourceDirectory = ChatGPTTestCertificateDirectory()
        try FileManager.default.createDirectory(at: sourceDirectory.url, withIntermediateDirectories: true)
        let source = sourceDirectory.url.appending(path: "custom.pem")
        let original = ["CODEX_CA_CERTIFICATE": source.path, "SSL_CERT_FILE": "/unchanged/fallback.pem"]
        let fixture = try await ChatGPTFixture.make(environment: original)
        try Data(fixture.authorityPEM.utf8).write(to: source)
        _ = try await fixture.coordinator.connectChatGPT()
        let managed = try #require(fixture.controller.environments.last)
        #expect(managed["CODEX_CA_CERTIFICATE"] != source.path)
        _ = try await fixture.coordinator.connectCodex()
        #expect(fixture.controller.environments.last == managed)
        fixture.store.failNextSave()
        await #expect(throws: (any Error).self) { try await fixture.coordinator.disconnectDesktopClients() }
        #expect(fixture.controller.environments.last == managed)
        #expect(fixture.store.configuration.codex.connected && fixture.store.configuration.chatgpt.connected)
        _ = try await fixture.coordinator.disconnectDesktopClients()
        #expect(fixture.controller.environments.last == original)
        #expect(!fixture.store.configuration.codex.connected && !fixture.store.configuration.chatgpt.connected)
        #expect(try String(contentsOf: source, encoding: .utf8) == fixture.authorityPEM)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A CA source changed during desktop quit cannot invalidate the prepared relaunch")
    func immutablePreparationSurvivesQuit() async throws {
        let sourceDirectory = ChatGPTTestCertificateDirectory()
        try FileManager.default.createDirectory(at: sourceDirectory.url, withIntermediateDirectories: true)
        let source = sourceDirectory.url.appending(path: "custom.pem")
        let fixture = try await ChatGPTFixture.make(environment: ["CODEX_CA_CERTIFICATE": source.path])
        try Data(fixture.authorityPEM.utf8).write(to: source)
        _ = try await fixture.coordinator.connectChatGPT()
        let managed = try #require(fixture.controller.environments.last)
        fixture.controller.onQuit = { try? FileManager.default.removeItem(at: source) }
        _ = try await fixture.coordinator.connectCodex()
        #expect(fixture.controller.running)
        #expect(fixture.controller.environments.last == managed)
        #expect(await fixture.coordinator.snapshot().chatGPTStatus == .connected)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("An unreadable inherited CA bundle fails before quitting the desktop")
    func unreadableInheritedTrust() async throws {
        let missing = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let fixture = try await ChatGPTFixture.make(environment: ["CODEX_CA_CERTIFICATE": missing.path])
        await #expect(throws: ChatGPTConnectionError.certificateBundleUnavailable) {
            try await fixture.coordinator.connectChatGPT()
        }
        #expect(!fixture.events.recorded.contains("quit"))
        #expect(!fixture.store.configuration.chatgpt.connected)
        #expect(await fixture.mainServer.isRunning)
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}

final class ChatGPTTestCertificateDirectory {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    deinit { try? FileManager.default.removeItem(at: url) }
}
