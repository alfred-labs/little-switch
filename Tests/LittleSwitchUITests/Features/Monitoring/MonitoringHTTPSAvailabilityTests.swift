import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Monitoring HTTPS availability")
struct MonitoringHTTPSAvailabilityTests {
    @Test("HTTPS requires a running listener identity and existing trust, without provisioning during polling")
    func availability() async throws {
        let issued = try GatewayTLSIdentityFactory.make()
        let identity = try GatewayTLSIdentity(
            certificatePEM: issued.certificatePEM,
            authorityPEM: issued.authorityPEM,
            keyPEM: issued.keyPEM
        )
        for (hasIdentity, trusted) in [(false, false), (false, true), (true, false), (true, true)] {
            let provisioner = MonitoringTLSProbe(identity: hasIdentity ? identity : nil, trusted: trusted)
            let coordinator = ApplicationCoordinator(
                configurationStore: RecordingConfigurationStore(configuration: .init()),
                secretStore: MemorySecretStore(),
                profileManager: TestClaudeProfileManager(),
                claudeController: TestClaudeController(),
                discoveryTransport: TestGatewayTransport(),
                gatewayTransport: TestGatewayTransport(),
                gatewayServerOverride: TestGatewayServer(),
                tlsProvisioner: provisioner
            )
            #expect(await !coordinator.snapshot().monitoringHTTPSAvailable)
            #expect(provisioner.events.recorded.isEmpty)
            let started = try await coordinator.start()
            #expect(started.monitoringHTTPSAvailable == (hasIdentity && trusted))
            #expect(await coordinator.snapshot().monitoringHTTPSAvailable == (hasIdentity && trusted))
            #expect(provisioner.events.recorded == ["identity"])
            await coordinator.shutdown()
            #expect(await !coordinator.snapshot().monitoringHTTPSAvailable)
        }
    }
}

private struct MonitoringTLSProbe: GatewayTLSProvisioning {
    let identity: GatewayTLSIdentity?
    let trusted: Bool
    let events = SharedEventLog()

    func identity(secretStore: any SecretStore) -> GatewayTLSIdentity? {
        events.append("identity")
        return identity
    }

    func isTrusted(secretStore: any SecretStore) -> Bool { trusted }

    func installTrust(secretStore: any SecretStore) -> GatewayTLSTrustOutcome {
        Issue.record("Monitoring must not install trust")
        return .init(isTrusted: false)
    }

    func revokeTrust(secretStore: any SecretStore) -> [GatewayTLSTrustFailure] {
        Issue.record("Monitoring must not revoke trust")
        return []
    }
}
