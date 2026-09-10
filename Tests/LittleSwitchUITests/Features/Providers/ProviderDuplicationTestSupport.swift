import AsyncHTTPClient
import Foundation
import LittleSwitchCore
import LittleSwitchTransport
import NIOCore
import NIOHTTP1

@testable import LittleSwitchUI

actor DuplicateCatalogTransport: UpstreamTransport {
    private let probeEntered = AsyncTestGate()
    private let probeReleased = AsyncTestGate()
    private var suspendsProbe = false
    private(set) var authorizationMatched: [Bool] = []
    private let expectedCredential: String

    init(expectedCredential: String = "original-key") {
        self.expectedCredential = expectedCredential
    }

    func resetAuthorizationChecks() {
        authorizationMatched = []
    }

    func suspendNextProbe() {
        suspendsProbe = true
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        if request.method == .GET, request.url.hasSuffix("/models") {
            authorizationMatched.append(
                request.headers.first(name: "authorization") == "Bearer \(expectedCredential)"
            )
        }
        if suspendsProbe, request.method == .POST {
            suspendsProbe = false
            await probeEntered.open()
            try await probeReleased.wait()
        }
        let isVersion = request.url.hasSuffix("/api/version")
        return HTTPClientResponse(
            status: isVersion ? .notFound : .ok,
            headers: ["content-type": "application/json"],
            body: .bytes(ByteBuffer(string: #"{"data":[{"id":"applied"}]}"#))
        )
    }

    func waitForProbe() async throws {
        try await probeEntered.wait(description: "duplicate route probe")
    }

    func releaseProbe() async {
        await probeReleased.open()
    }
}

actor DuplicateScriptRunner: CredentialScriptRunning {
    private(set) var calls: [String] = []

    func run(scriptPath: String) async throws -> CredentialScriptRun {
        calls.append(scriptPath)
        return CredentialScriptRun(token: "fresh-script-key", standardError: "Fresh run")
    }
}

@MainActor
struct ProviderDuplicationFixture {
    let source: Provider
    let store: ScriptedConfigurationStore
    let secrets: ScriptedSecretStore
    let coordinator: ApplicationCoordinator

    static func make(
        credential: String? = "original-key",
        credentialSource: CredentialSource = .manual,
        transport: any UpstreamTransport = DuplicateCatalogTransport(),
        scriptRunner: any CredentialScriptRunning = DuplicateScriptRunner()
    ) async throws -> Self {
        let source = Provider(
            name: "z.ai",
            baseURL: "https://example.com/v1",
            authMode: .bearer,
            credentialSource: credentialSource,
            credentialScriptPath: credentialSource == .script ? "/tmp/provider-login.sh" : nil,
            credentialRefreshInterval: 900,
            models: [DiscoveredModel(id: "applied", contextWindowOverride: 1_000_000)],
            lastRefresh: Date(timeIntervalSince1970: 123),
            status: .ready,
            maximumParallelRequests: 7,
            imageInputOverride: .enabled,
            responsesWireOverride: .chatCompletions,
            wireProbe: ProviderWireProbe(
                messages: .absent, responses: .absent, chatCompletions: .absent
            )
        )
        let store = ScriptedConfigurationStore(
            configuration: AppConfiguration(
                providers: [source],
                mappings: ["claude-sonnet-5": ModelMapping(providerID: source.id, modelID: "applied")]
            )
        )
        let secrets = ScriptedSecretStore(
            values: credential.map { [.provider(source.id): $0] } ?? [:]
        )
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: secrets,
            profileManager: ScriptedClaudeProfileManager(),
            claudeController: ScriptedApplicationController(),
            discoveryTransport: transport,
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer(),
            credentialScriptRunner: scriptRunner
        )
        _ = try await coordinator.start()
        return Self(source: source, store: store, secrets: secrets, coordinator: coordinator)
    }

    func input(id: UUID = UUID(), credential: String? = nil) -> ProviderInput {
        ProviderInput(
            id: id,
            intent: .duplicate(sourceID: source.id),
            name: "z.ai copy",
            baseURL: source.baseURL,
            authMode: source.authMode,
            credential: credential,
            credentialSource: source.credentialSource,
            scriptPath: source.credentialScriptPath,
            credentialRefreshInterval: source.credentialRefreshInterval,
            contextOverrides: ["applied": 1_000_000],
            maximumParallelRequests: source.maximumParallelRequests,
            imageInputOverride: source.imageInputOverride,
            responsesWireOverride: source.responsesWireOverride
        )
    }
}
