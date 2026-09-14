import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Application coordinator")
struct ApplicationCoordinatorTests {
    @Test("The coordinator passes its traffic recorder to the live gateway builder")
    func trafficRecorderWiring() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "little-switch-recorder-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConfigurationStore(
            fileURL: root.appending(path: "config.json"),
            backupDirectory: root.appending(path: "backups")
        )
        try store.save(AppConfiguration())
        let recorder = TestTrafficRecorder()
        let builder = CapturingGatewayBuilder(expectedRecorder: recorder)
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: ClaudeProfileManager(
                paths: ClaudeProfilePaths(applicationSupport: root)
            ),
            claudeController: TestClaudeController(),
            discoveryTransport: StaticCatalogTransport(),
            gatewayTransport: TestGatewayTransport(),
            gatewayBuilder: builder,
            trafficRecorder: recorder
        )

        _ = try await coordinator.start()
        #expect(builder.receivedExpectedRecorder)
        await coordinator.shutdown()
    }

    @Test("Unassigning the last route is allowed while disconnected")
    func disconnectedUnmapLastRouteAllowed() async throws {
        let fixture = try await ConnectedCoordinatorFixture.make(connected: false)
        defer { fixture.removeFiles() }

        let unmapped = try await fixture.coordinator.setMapping(
            routeID: "claude-opus-5",
            mapping: nil
        )

        #expect(unmapped.configuration.mappings.isEmpty)
        #expect(try fixture.store.load().mappings.isEmpty)
    }

    @Test("Provider deletion removes its mappings from disk and routing")
    func providerDeletionRemovesMappingsLive() async throws {
        let fixture = try await ConnectedCoordinatorFixture.make()
        defer { fixture.removeFiles() }

        let deleted = try await fixture.coordinator.deleteProvider(
            id: fixture.providerID
        )

        #expect(deleted.configuration.mappings.isEmpty)
        #expect(try fixture.store.load().mappings.isEmpty)
        #expect(await fixture.gatewayState.capture().mappings.isEmpty)
    }

    @Test("Disconnected edits persist immediately and never create a draft")
    func disconnectedEditsPersist() async throws {
        let fixture = try await ConnectedCoordinatorFixture.make(connected: false)
        defer { fixture.removeFiles() }

        _ = try await fixture.coordinator.setAutoMode(false)

        #expect(!(try fixture.store.load()).autoMode)
    }

    @Test("A failed disconnected mapping save restores coordinator memory")
    func disconnectedMappingSaveRollback() async throws {
        let fixture = try await FailingSaveFixture.make()
        defer { fixture.removeFiles() }
        fixture.store.failNextSave()

        await #expect(throws: FailNextConfigurationStore.Error.injected) {
            _ = try await fixture.coordinator.setMapping(
                routeID: "claude-opus-5",
                mapping: ModelMapping(
                    providerID: fixture.providerID,
                    modelID: "replacement"
                )
            )
        }

        #expect(
            (await fixture.coordinator.snapshot()).configuration
                == fixture.appliedConfiguration
        )
        #expect(try fixture.store.load() == fixture.appliedConfiguration)
    }

    @Test("A failed disconnected Auto mode save restores coordinator memory")
    func disconnectedAutoModeSaveRollback() async throws {
        let fixture = try await FailingSaveFixture.make()
        defer { fixture.removeFiles() }
        fixture.store.failNextSave()

        await #expect(throws: FailNextConfigurationStore.Error.injected) {
            _ = try await fixture.coordinator.setAutoMode(false)
        }

        #expect(
            (await fixture.coordinator.snapshot()).configuration
                == fixture.appliedConfiguration
        )
        #expect(try fixture.store.load() == fixture.appliedConfiguration)
    }

    @Test("Catalog indicator persists and hot-swaps the gateway catalog only")
    func modelIndicatorAppliesLive() async throws {
        let fixture = try await ConnectedCoordinatorFixture.make()
        defer { fixture.removeFiles() }

        let unchanged = try await fixture.coordinator.setModelIndicator(.mapsTo)
        #expect(unchanged.configuration.modelIndicator == .mapsTo)
        #expect(try fixture.store.load() == fixture.appliedConfiguration)

        let changed = try await fixture.coordinator.setModelIndicator(.equilibrium)

        #expect(changed.configuration.modelIndicator == .equilibrium)
        #expect(try fixture.store.load().modelIndicator == .equilibrium)
        #expect(await fixture.gatewayState.capture().modelIndicator == .equilibrium)
        // Pure presentation: no profile rewrite, no Desktop relaunch.
        #expect(fixture.controller.quitCount == 0)
        #expect(fixture.controller.openCount == 0)
    }

    @Test("A failed catalog indicator save restores coordinator memory")
    func modelIndicatorSaveRollback() async throws {
        let fixture = try await FailingSaveFixture.make()
        defer { fixture.removeFiles() }
        fixture.store.failNextSave()

        await #expect(throws: FailNextConfigurationStore.Error.injected) {
            _ = try await fixture.coordinator.setModelIndicator(.routed)
        }

        #expect(
            (await fixture.coordinator.snapshot()).configuration
                == fixture.appliedConfiguration
        )
        #expect(try fixture.store.load() == fixture.appliedConfiguration)
    }

    @Test("Provider context overrides persist, clear, and survive refresh")
    func providerContextOverrides() async throws {
        let fixture = try await ConnectedCoordinatorFixture.make(connected: false)
        defer { fixture.removeFiles() }

        let overridden = try await fixture.coordinator.saveProvider(
            ProviderInput(
                id: fixture.providerID,
                name: "Local",
                baseURL: "http://127.0.0.1:11434",
                authMode: .none,
                contextOverrides: ["applied": 1_000_000]
            ))

        #expect(
            overridden.configuration.providers.first?.models
                .first { $0.id == "applied" }?.contextWindowOverride == 1_000_000
        )
        _ = try await fixture.coordinator.refreshProvider(id: fixture.providerID)
        #expect(
            (try fixture.store.load()).providers.first?.models
                .first { $0.id == "applied" }?.contextWindowOverride == 1_000_000
        )

        let cleared = try await fixture.coordinator.saveProvider(
            ProviderInput(
                id: fixture.providerID,
                name: "Local",
                baseURL: "http://127.0.0.1:11434",
                authMode: .none,
                contextOverrides: [:]
            ))
        #expect(
            cleared.configuration.providers.first?.models
                .first { $0.id == "applied" }?.contextWindowOverride == nil
        )
    }

    @Test("A probe detecting less than 1M deactivates a saved 1M override")
    func contradicting1MOverrideDeactivates() async throws {
        let transport = StaticCatalogTransport()
        let fixture = try await ConnectedCoordinatorFixture.make(
            connected: false,
            discoveryTransport: transport
        )
        defer { fixture.removeFiles() }

        // The 1M override was saved while capacity was unknown.
        let saved = try await fixture.coordinator.saveProvider(
            ProviderInput(
                id: fixture.providerID,
                name: "Local",
                baseURL: "http://127.0.0.1:11434",
                authMode: .none,
                contextOverrides: ["applied": 1_000_000]
            ))
        #expect(
            saved.configuration.providers.first?.models
                .first { $0.id == "applied" }?.contextWindowOverride == 1_000_000
        )

        // Re-detection reports 400K: the override is dropped.
        await transport.serveCatalog(
            #"{"data":[{"id":"applied","context_window":400000},{"id":"replacement"}]}"#
        )
        let refreshed = try await fixture.coordinator.refreshProvider(id: fixture.providerID)
        let model = refreshed.configuration.providers.first?.models
            .first { $0.id == "applied" }
        #expect(model?.detectedContextWindow == 400_000)
        #expect(model?.contextWindowOverride == nil)
        #expect(model?.supports1MContext == false)
    }

    @Test("Provider context overrides reject unknown models")
    func invalidProviderContextOverride() async throws {
        let fixture = try await ConnectedCoordinatorFixture.make(connected: false)
        defer { fixture.removeFiles() }

        await #expect(throws: ApplicationCoordinator.Error.invalidModelContext) {
            _ = try await fixture.coordinator.saveProvider(
                ProviderInput(
                    id: fixture.providerID,
                    name: "Local",
                    baseURL: "http://127.0.0.1:11434",
                    authMode: .none,
                    contextOverrides: ["missing": 1_000_000]
                ))
        }

        #expect(try fixture.store.load() == fixture.appliedConfiguration)
    }

    @Test("A listener collision has a product-facing error")
    func listenerCollisionMessage() {
        #expect(
            ApplicationCoordinator.Error.gatewayUnavailable.errorDescription
                == "Port 11436 is already in use. Quit the other LittleSwitch instance, then reopen the app."
        )
    }
}

private final class RecordingTLSProvisioner: GatewayTLSProvisioning, @unchecked Sendable {
    private let lock = NSLock()
    private var installs = 0
    private let outcome: GatewayTLSTrustOutcome

    init(outcome: GatewayTLSTrustOutcome = GatewayTLSTrustOutcome(isTrusted: true)) {
        self.outcome = outcome
    }

    var installCalls: Int {
        lock.lock()
        defer { lock.unlock() }
        return installs
    }

    func identity(secretStore: any SecretStore) -> GatewayTLSIdentity? {
        nil
    }

    func installTrust(secretStore: any SecretStore) -> GatewayTLSTrustOutcome {
        lock.lock()
        defer { lock.unlock() }
        installs += 1
        return outcome
    }

    func isTrusted(secretStore: any SecretStore) -> Bool {
        outcome.isTrusted
    }

    func revokeTrust(secretStore: any SecretStore) -> [GatewayTLSTrustFailure] {
        lock.lock()
        defer { lock.unlock() }
        installs -= 1
        return []
    }
}

extension ApplicationCoordinatorTests {
    @Test("Connecting installs the gateway TLS leaf trust")
    func connectInstallsTLSTrust() async throws {
        let provisioner = RecordingTLSProvisioner()
        let fixture = try await ConnectedCoordinatorFixture.make(
            connected: false,
            tlsProvisioner: provisioner
        )
        defer { fixture.removeFiles() }

        _ = try await fixture.coordinator.connect()
        _ = try await fixture.coordinator.setAutoMode(false)

        #expect(provisioner.installCalls == 1)
        _ = try await fixture.coordinator.disconnect()
        // The anchor survives the toggle — only a renewal purges it — so
        // reconnecting never prompts again.
        #expect(provisioner.installCalls == 1)
        await fixture.coordinator.shutdown()
    }

    @Test("A refused trust leaves the profile on plain http")
    func connectKeepsHTTPWhenTrustIsRefused() async throws {
        // The Desktop reads the advertised origin literally, so an https
        // origin the anchor cannot vouch for is worse than no https at
        // all. The failure behind it is what reaches the log.
        let provisioner = RecordingTLSProvisioner(
            outcome: GatewayTLSTrustOutcome(
                isTrusted: false,
                failures: [.anchorMissingAfterInstall]
            )
        )
        let fixture = try await ConnectedCoordinatorFixture.make(
            connected: false,
            tlsProvisioner: provisioner
        )
        defer { fixture.removeFiles() }

        _ = try await fixture.coordinator.connect()

        let paths = ClaudeProfilePaths(applicationSupport: fixture.root)
        let data = try Data(contentsOf: paths.profile)
        let profile = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(
            profile["inferenceGatewayBaseUrl"] as? String
                == ClaudeProfileIdentity.gatewayHTTPBaseURL
        )
        await fixture.coordinator.shutdown()
    }

    @Test("A trusted anchor upgrades the managed Claude Code origin to https")
    func trustedAnchorUpgradesClaudeCodeOrigin() async throws {
        let fixture = try await ClaudeCodeCoordinatorFixture.make(
            tlsProvisioner: RecordingTLSProvisioner()
        )

        _ = try await fixture.coordinator.connectClaudeCode()

        #expect(
            fixture.profile.activations.last?.environment["ANTHROPIC_BASE_URL"]
                == ClaudeProfileIdentity.gatewayBaseURL
        )
    }

    @Test("An untrusted anchor keeps the managed Claude Code origin on http")
    func untrustedAnchorKeepsClaudeCodeHTTPOrigin() async throws {
        // The terminal CLI has no in-app fallback, so the managed origin
        // follows the same trust gate as the Desktop profile.
        let fixture = try await ClaudeCodeCoordinatorFixture.make(
            tlsProvisioner: RecordingTLSProvisioner(
                outcome: GatewayTLSTrustOutcome(isTrusted: false)
            )
        )

        _ = try await fixture.coordinator.connectClaudeCode()

        #expect(
            fixture.profile.activations.last?.environment["ANTHROPIC_BASE_URL"]
                == ClaudeProfileIdentity.gatewayHTTPBaseURL
        )
    }
}
