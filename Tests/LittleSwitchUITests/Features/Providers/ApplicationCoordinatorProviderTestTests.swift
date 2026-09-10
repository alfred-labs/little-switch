import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore
@testable import LittleSwitchUI

private final class TestScriptRunner: CredentialScriptRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var scripts: [String] = []
    private let standardError: String
    private let failure: (any Error)?

    init(standardError: String = "", failure: (any Error)? = nil) {
        self.standardError = standardError
        self.failure = failure
    }

    var calls: [String] {
        lock.withLock { scripts }
    }

    func run(scriptPath: String) async throws -> CredentialScriptRun {
        lock.withLock { scripts.append(scriptPath) }
        if let failure {
            throw failure
        }
        return CredentialScriptRun(token: "scripted-token", standardError: standardError)
    }
}

/// Serves any catalog while recording the GET URLs the coordinator asked
/// for — the split-surface Test regression needs the exact discovery URL,
/// not just a passing outcome.
private actor RecordingCatalogTransport: UpstreamTransport {
    private(set) var getURLs: [String] = []

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        if request.method == .GET {
            getURLs.append(request.url)
        }
        return HTTPClientResponse(
            status: .ok,
            headers: ["content-type": "application/json"],
            body: .bytes(ByteBuffer(string: #"{"data":[{"id":"applied"}]}"#))
        )
    }
}

@MainActor
private struct Fixture {
    let providerID: UUID
    let secrets: ScriptedSecretStore
    let runner: TestScriptRunner
    let coordinator: ApplicationCoordinator

    static func make(
        authMode: AuthMode = .bearer,
        credentialSource: CredentialSource = .manual,
        configuredScriptPath: String? = nil,
        runner: TestScriptRunner = TestScriptRunner(),
        discoveryTransport: any UpstreamTransport = StaticCatalogTransport()
    ) async throws -> Self {
        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: authMode,
            credentialSource: credentialSource,
            credentialScriptPath: configuredScriptPath,
            credentialRefreshInterval: 900,
            models: [DiscoveredModel(id: "applied")],
            status: .ready
        )
        let store = ScriptedConfigurationStore(
            configuration: AppConfiguration(providers: [provider])
        )
        let secrets = ScriptedSecretStore(
            values: [.provider(providerID): "stored-token"]
        )
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: secrets,
            profileManager: ScriptedClaudeProfileManager(),
            claudeController: ScriptedApplicationController(),
            discoveryTransport: discoveryTransport,
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer(),
            credentialScriptRunner: runner
        )
        _ = try await coordinator.start()
        return Self(
            providerID: providerID,
            secrets: secrets,
            runner: runner,
            coordinator: coordinator
        )
    }
}

@MainActor
@Suite("Application coordinator provider test")
struct CoordinatorProviderTestTests {
    @Test("Testing a script provider runs the script and probes the endpoint")
    func scriptTestPasses() async throws {
        let fixture = try await Fixture.make(
            authMode: .bearer,
            credentialSource: .script,
            configuredScriptPath: "printf saved-token",
            runner: TestScriptRunner(standardError: "Success! Logged in.")
        )

        let message = try await fixture.coordinator.testProvider(
            ProviderInput(
                id: fixture.providerID,
                name: "Local",
                baseURL: "http://127.0.0.1:11434",
                authMode: .bearer,
                credentialSource: .script
            )
        )
        #expect(message == "Success! Logged in.")
        #expect(fixture.runner.calls == ["printf saved-token"])
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A script that prints a token cannot pass without a reachable endpoint")
    func scriptValidButEndpointDownFailsAuthentication() async throws {
        let fixture = try await Fixture.make(
            authMode: .bearer,
            credentialSource: .script,
            configuredScriptPath: "printf saved-token",
            runner: TestScriptRunner(standardError: "Success! Logged in.")
        )

        await #expect(throws: ProviderEndpoint.Error.invalidURL) {
            _ = try await fixture.coordinator.testProvider(
                ProviderInput(
                    id: fixture.providerID,
                    name: "Local",
                    baseURL: "https://",
                    authMode: .bearer,
                    credentialSource: .script
                )
            )
        }
        // The script stage itself succeeded: its stderr is recorded, and no
        // failure badge shadows it.
        let failures = await fixture.coordinator.snapshot().credentialRefreshFailures
        #expect(failures[fixture.providerID] == nil)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Testing a script provider without a path is rejected")
    func scriptTestRequiresPath() async throws {
        let fixture = try await Fixture.make(
            authMode: .bearer,
            credentialSource: .script)

        await #expect(throws: ApplicationCoordinator.Error.missingCredentialScript) {
            _ = try await fixture.coordinator.testProvider(
                ProviderInput(
                    id: fixture.providerID,
                    name: "Local",
                    baseURL: "http://127.0.0.1:11434",
                    authMode: .bearer,
                    credentialSource: .script,
                    scriptPath: "  \n "
                )
            )
        }
        #expect(fixture.runner.calls.isEmpty)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Testing a script provider with no configured path falls back to the row")
    func scriptTestFallsBackToConfiguredPath() async throws {
        let fixture = try await Fixture.make(
            authMode: .bearer,
            credentialSource: .script,
            configuredScriptPath: "printf saved-token"
        )

        let message = try await fixture.coordinator.testProvider(
            ProviderInput(
                id: fixture.providerID,
                name: "Local",
                baseURL: "http://127.0.0.1:11434",
                authMode: .bearer,
                credentialSource: .script,
                scriptPath: ""
            )
        )
        #expect(message == nil)
        #expect(fixture.runner.calls == ["printf saved-token"])
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A failing script test surfaces the error and records the outcome")
    func scriptTestFailureRecordsOutcome() async throws {
        let failure = CredentialScriptError(
            reason: .exit(status: 5),
            standardError: "denied"
        )
        let fixture = try await Fixture.make(
            authMode: .bearer,
            credentialSource: .script,
            configuredScriptPath: "printf saved-token",
            runner: TestScriptRunner(failure: failure)
        )

        do {
            _ = try await fixture.coordinator.testProvider(
                ProviderInput(
                    id: fixture.providerID,
                    name: "Local",
                    baseURL: "http://127.0.0.1:11434",
                    authMode: .bearer,
                    credentialSource: .script
                )
            )
            Issue.record("The test should have failed with the script error")
        } catch let error as CredentialScriptError {
            #expect(error == failure)
        }

        let failures = await fixture.coordinator.snapshot().credentialRefreshFailures
        #expect(
            failures[fixture.providerID]
                == "The credential script exited with status 5. denied"
        )
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Testing a bearer provider probes discovery with the credential")
    func bearerTestPassesThroughDiscovery() async throws {
        let fixture = try await Fixture.make(authMode: .none)

        let message = try await fixture.coordinator.testProvider(
            ProviderInput(
                name: "Local",
                baseURL: "http://127.0.0.1:11434",
                authMode: .bearer,
                credential: "manual-key"
            )
        )
        #expect(message == nil)
        #expect(fixture.runner.calls.isEmpty)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A manual test of a split-surface provider probes /models at the base root")
    func manualSplitSurfaceTestProbesRootModels() async throws {
        let transport = RecordingCatalogTransport()
        let fixture = try await Fixture.make(discoveryTransport: transport)

        let message = try await fixture.coordinator.testProvider(
            ProviderInput(
                name: "z.ai",
                baseURL: "https://api.z.ai/api/coding/paas/v4",
                authMode: .bearer,
                credential: "manual-key",
                anthropicBaseURL: "https://api.z.ai/api/anthropic"
            )
        )
        #expect(message == nil)
        let urls = await transport.getURLs
        #expect(urls.contains("https://api.z.ai/api/coding/paas/v4/models"))
        #expect(!urls.contains("https://api.z.ai/api/coding/paas/v4/v1/models"))
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A script test of a split-surface provider probes /models at the base root")
    func scriptSplitSurfaceTestProbesRootModels() async throws {
        let transport = RecordingCatalogTransport()
        let fixture = try await Fixture.make(
            authMode: .bearer,
            credentialSource: .script,
            configuredScriptPath: "printf saved-token",
            discoveryTransport: transport
        )

        let message = try await fixture.coordinator.testProvider(
            ProviderInput(
                id: fixture.providerID,
                name: "z.ai",
                baseURL: "https://api.z.ai/api/coding/paas/v4",
                authMode: .bearer,
                credentialSource: .script,
                anthropicBaseURL: "https://api.z.ai/api/anthropic"
            )
        )
        #expect(message == nil)
        let urls = await transport.getURLs
        #expect(urls.contains("https://api.z.ai/api/coding/paas/v4/models"))
        #expect(!urls.contains("https://api.z.ai/api/coding/paas/v4/v1/models"))
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Testing a new provider without an identifier still runs the script")
    func scriptTestWithoutIdentifierRuns() async throws {
        let fixture = try await Fixture.make(
            authMode: .bearer,
            credentialSource: .script,
            configuredScriptPath: "printf saved-token",
            runner: TestScriptRunner(standardError: "Success! Logged in.")
        )

        let message = try await fixture.coordinator.testProvider(
            ProviderInput(
                name: "Local",
                baseURL: "http://127.0.0.1:11434",
                authMode: .bearer,
                credentialSource: .script,
                scriptPath: "printf saved-token"
            )
        )
        #expect(message == "Success! Logged in.")
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A failing test of a new provider surfaces the error without a badge")
    func failingScriptTestWithoutIdentifierSurfacesError() async throws {
        let failure = CredentialScriptError(reason: .exit(status: 6), standardError: "gone")
        let fixture = try await Fixture.make(
            authMode: .bearer,
            credentialSource: .script,
            configuredScriptPath: "printf saved-token",
            runner: TestScriptRunner(failure: failure)
        )

        await #expect(throws: CredentialScriptError(reason: .exit(status: 6), standardError: "gone")) {
            _ = try await fixture.coordinator.testProvider(
                ProviderInput(
                    name: "Local",
                    baseURL: "http://127.0.0.1:11434",
                    authMode: .bearer,
                    credentialSource: .script,
                    scriptPath: "printf saved-token"
                )
            )
        }
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Testing a bearer provider with an invalid URL is rejected")
    func bearerTestRejectsInvalidURL() async throws {
        let fixture = try await Fixture.make(authMode: .none)

        await #expect(throws: ProviderEndpoint.Error.invalidURL) {
            _ = try await fixture.coordinator.testProvider(
                ProviderInput(
                    id: fixture.providerID,
                    name: "Local",
                    baseURL: "https://",
                    authMode: .bearer,
                    credential: "manual-key"
                )
            )
        }
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}

/// A non-LocalizedError, so the save flow's fallback message runs.
private struct UnlocalizedScriptFailure: Error, CustomStringConvertible {
    var description: String { "plain failure" }
}

@MainActor
@Suite("Application coordinator credential script failures")
struct CoordinatorCredentialScriptFailureTests {
    @Test("A failing save script surfaces its error and records the failure")
    func scriptSaveFailureRecordsOutcome() async throws {
        let failure = CredentialScriptError(
            reason: .exit(status: 3),
            standardError: "vault: permission denied"
        )
        let fixture = try await Fixture.make(
            credentialSource: .script,
            configuredScriptPath: "printf saved-token",
            runner: TestScriptRunner(failure: failure)
        )

        do {
            _ = try await fixture.coordinator.saveProvider(
                ProviderInput(
                    id: fixture.providerID,
                    name: "Local",
                    baseURL: "http://127.0.0.1:11434",
                    authMode: .bearer,
                    credentialSource: .script,
                    scriptPath: "exit 3",
                    credentialRefreshInterval: 900
                )
            )
            Issue.record("The save should have failed with the script error")
        } catch let error as CredentialScriptError {
            #expect(error == failure)
        }

        let failures = await fixture.coordinator.snapshot().credentialRefreshFailures
        #expect(failures[fixture.providerID] == "The credential script exited with status 3. vault: permission denied")
        await fixture.coordinator.shutdown(mode: .handoff)

        // A non-LocalizedError falls back to its description.
        let unlocalized = try await Fixture.make(
            credentialSource: .script,
            configuredScriptPath: "printf saved-token",
            runner: TestScriptRunner(failure: UnlocalizedScriptFailure())
        )
        do {
            _ = try await unlocalized.coordinator.saveProvider(
                ProviderInput(
                    id: unlocalized.providerID,
                    name: "Local",
                    baseURL: "http://127.0.0.1:11434",
                    authMode: .bearer,
                    credentialSource: .script,
                    scriptPath: "exit 4",
                    credentialRefreshInterval: 900
                )
            )
            Issue.record("The save should have failed with the unlocalized error")
        } catch is UnlocalizedScriptFailure {
        }
        let fallbacks = await unlocalized.coordinator.snapshot().credentialRefreshFailures
        #expect(fallbacks[unlocalized.providerID] == "plain failure")
        await unlocalized.coordinator.shutdown(mode: .handoff)
    }
}
