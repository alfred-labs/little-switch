import Foundation
import LittleSwitchCore
import LittleSwitchSearch
import Testing

@testable import LittleSwitchUI

@Suite("Application coordinator contracts")
struct ApplicationCoordinatorContractsTests {
    @Test("Every coordinator error has stable product-facing copy")
    func errorDescriptions() {
        let expected: [(ApplicationCoordinator.Error, String)] = [
            (.codexUnavailable, "Codex desktop integration is unavailable."),
            (.claudeCodeUnavailable, "Claude Code integration is unavailable."),
            (
                .claudeCodeRecoveryRequired,
                "Restore the previous Claude Code settings before connecting."
            ),
            (.openCodeUnavailable, "OpenCode integration is unavailable."),
            (
                .openCodeRecoveryRequired,
                "Restore the previous OpenCode settings before connecting."
            ),
            (.noExposedOpenCodeModel, "Expose at least one model before connecting OpenCode."),
            (
                .codexApplyRequiredForOpenCode,
                "Apply the pending Codex model exposure before applying OpenCode."
            ),
            (.duplicateProviderName, "Provider names must be unique."),
            (.invalidProviderName, "Enter a provider name."),
            (
                .providerDuplicationSourceUnavailable,
                "The original provider is no longer available. Choose another provider to duplicate."
            ),
            (
                .missingOriginalProviderCredential,
                "The original provider has no saved key. Enter an API token for this copy."
            ),
            (.invalidMapping, "Choose a model discovered from an available provider."),
            (
                .invalidModelContext,
                "Enter a positive context window for a discovered model."
            ),
            (.invalidWebSearchConfiguration, "Check the web search limits."),
            (.missingFirecrawlCredential, "Enter a Firecrawl API key for Cloud search."),
            (.missingTavilyCredential, "Enter a Tavily API key for web search."),
            (.missingBraveCredential, "Enter a Brave API key for web search."),
            (.missingExaCredential, "Enter an Exa API key for web search."),
            (.missingCredentialScript, "Enter the shell script that prints the credential."),
            (.noMappedModel, "Map at least one Claude model before connecting."),
            (.noExposedCodexModel, "Expose at least one model before connecting Codex."),
            (
                .noMappedClaudeCodeModel,
                "Map at least one Claude model before connecting Claude Code."
            ),
            (
                .gatewayUnavailable,
                "Port 11436 is already in use. Quit the other LittleSwitch instance, then reopen the app."
            ),
            (
                .rollbackFailed,
                "Some previous settings could not be restored. Review the affected settings before trying again."
            ),
            (
                .relaunchFailed,
                "Claude Desktop kept its previous settings: the app could not be restarted. Relaunch it manually to pick the change up."
            ),
        ]

        #expect(expected.map(\.0.errorDescription) == expected.map { Optional($0.1) })
    }

    @Test("Coordinator inputs preserve every supplied value")
    func inputInitializers() {
        let providerID = UUID()
        let provider = ProviderInput(
            id: providerID,
            name: " Provider ",
            baseURL: "https://example.com/v1",
            authMode: .xAPIKey,
            credential: "secret",
            contextOverrides: ["model": 262_144]
        )
        #expect(provider.id == providerID)
        #expect(provider.name == " Provider ")
        #expect(provider.baseURL == "https://example.com/v1")
        #expect(provider.authMode == AuthMode.xAPIKey)
        #expect(provider.credential == "secret")
        #expect(provider.contextOverrides == ["model": 262_144])

        let minimalProvider = ProviderInput(
            name: "Minimal",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none
        )
        #expect(minimalProvider.id == nil)
        #expect(minimalProvider.credential == nil)
        #expect(minimalProvider.contextOverrides == nil)

        let configuration = WebSearchConfiguration(
            provider: .firecrawl,
            resultsLimit: 12,
            maximumUses: 3
        )
        let webSearch = WebSearchInput(configuration: configuration, credential: "firecrawl")
        #expect(webSearch.configuration == configuration)
        #expect(webSearch.credential == "firecrawl")
        #expect(WebSearchInput(configuration: .disabled).credential == nil)
    }

    @Test("Live gateway adapters preserve an empty build context without binding")
    func gatewayBuildContext() async throws {
        let recorder = TestTrafficRecorder()
        let transport = TestGatewayTransport()
        let context = GatewayBuildContext(
            state: GatewayState(
                snapshot: RoutingSnapshot(generation: 0, providers: [], mappings: [:])
            ),
            transport: transport,
            secretStore: MemorySecretStore(),
            listenPort: 0,
            requiredAuthorityPort: nil,
            trafficRecorder: recorder
        )

        let liveGateway = LiveGatewayBuilder().makeGateway(context)
        #expect(!(await liveGateway.isRunning))
        await liveGateway.stop()

        let capturingBuilder = CapturingGatewayBuilder(
            expectedRecorder: recorder
        )
        let factory = LiveGatewayFactory(builder: capturingBuilder)
        let injectedGateway = factory.makeGateway(context)
        #expect(!(await injectedGateway.isRunning))
        #expect(capturingBuilder.receivedExpectedRecorder)
    }

    @Test("Startup and transport builders implement their complete lifecycle")
    func startupAndTransportBuilders() async throws {
        let observer = LiveGatewayStartupObserver()
        await observer.joinedStartup()
        await observer.readyToPublishStartup()
        await observer.waitingForAbandonedStartupCleanup()
        await observer.cancellingStartupWaiter()
        await observer.cancelledStartupWaiter()
        await observer.stoppingAbandonedStartup()

        let injected = TestGatewayTransport()
        let injectedBuilder = InjectedGatewayTransportBuilder(transport: injected)
        let first = await injectedBuilder.makeTransport()
        #expect(first as AnyObject === injected)

        let fallback = await injectedBuilder.makeTransport()
        try await fallback.shutdown()

        let live = await LiveGatewayTransportBuilder().makeTransport()
        try await live.shutdown()
    }
}
