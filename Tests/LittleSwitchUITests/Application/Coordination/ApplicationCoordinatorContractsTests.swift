import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import LittleSwitchSearch
import Testing

@testable import LittleSwitchUI

@Suite("Application coordinator contracts")
struct ApplicationCoordinatorContractsTests {
    @Test("Every coordinator error has stable product-facing copy")
    func errorDescriptions() {
        let expected: [(ApplicationCoordinator.Error, String)] = [
            (.codexUnavailable, L10n.string("Codex desktop integration is unavailable.")),
            (.claudeCodeUnavailable, L10n.string("Claude Code integration is unavailable.")),
            (
                .claudeDesktopProfileChanged,
                L10n.string(
                    "Claude Desktop settings changed outside LittleSwitch. Disconnect and reconnect before applying.")
            ),
            (
                .claudeCodeRecoveryRequired,
                L10n.string("Restore the previous Claude Code settings before connecting.")
            ),
            (.openCodeUnavailable, L10n.string("OpenCode integration is unavailable.")),
            (
                .openCodeRecoveryRequired,
                L10n.string("Restore the previous OpenCode settings before connecting.")
            ),
            (.noExposedOpenCodeModel, L10n.string("Expose at least one model before connecting OpenCode.")),
            (
                .codexApplyRequiredForOpenCode,
                L10n.string("Apply the pending Codex model exposure before applying OpenCode.")
            ),
            (.duplicateProviderName, L10n.string("Provider names must be unique.")),
            (.invalidProviderName, L10n.string("Enter a provider name.")),
            (
                .providerDuplicationSourceUnavailable,
                L10n.string("The original provider is no longer available. Choose another provider to duplicate.")
            ),
            (
                .missingOriginalProviderCredential,
                L10n.string("The original provider has no saved key. Enter an API token for this copy.")
            ),
            (.invalidMapping, L10n.string("Choose a model discovered from an available provider.")),
            (
                .invalidModelContext,
                L10n.string("Enter a positive context window for a discovered model.")
            ),
            (.invalidWebSearchConfiguration, L10n.string("Check the web search limits.")),
            (.missingFirecrawlCredential, L10n.string("Enter a Firecrawl API key for Cloud search.")),
            (.missingTavilyCredential, L10n.string("Enter a Tavily API key for web search.")),
            (.missingBraveCredential, L10n.string("Enter a Brave API key for web search.")),
            (.missingExaCredential, L10n.string("Enter an Exa API key for web search.")),
            (.missingCredentialScript, L10n.string("Enter the shell script that prints the credential.")),
            (.noMappedModel, L10n.string("Map at least one Claude model before connecting.")),
            (.noExposedCodexModel, L10n.string("Expose at least one model before connecting Codex.")),
            (
                .noMappedClaudeCodeModel,
                L10n.string("Map at least one Claude model before connecting Claude Code.")
            ),
            (
                .gatewayUnavailable,
                L10n.string("Port 11436 is already in use. Quit the other LittleSwitch instance, then reopen the app.")
            ),
            (
                .rollbackFailed,
                L10n.string(
                    "Some previous settings could not be restored. Review the affected settings before trying again.")
            ),
            (
                .relaunchFailed,
                L10n.string(
                    "Claude Desktop kept its previous settings: the app could not be restarted. Relaunch it manually to pick the change up."
                )
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
