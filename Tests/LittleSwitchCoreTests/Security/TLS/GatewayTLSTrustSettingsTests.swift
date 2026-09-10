import Foundation
import Security
import Testing

@testable import LittleSwitchCore

@Suite("Gateway TLS trust settings")
struct GatewayTLSTrustSettingsTests {
    @Test("The trust result bridges to the number Security.framework reads")
    func resultBridgesToNumber() throws {
        let settings = try #require(LiveGatewayTLSTrustInstaller.trustSettings.first)
        // Handed over as the bare `SecTrustSettingsResult` this value does
        // not bridge into the CFDictionary, and the framework answers
        // errSecParam (-50) while installing no anchor at all — measured
        // against the gateway's own leaf.
        let result = try #require(settings[kSecTrustSettingsResult as String] as? NSNumber)
        #expect(result.uint32Value == SecTrustSettingsResult.trustRoot.rawValue)
    }

    @Test("The anchor is trusted for TLS alone, not for every purpose")
    func policyRestrictsToTLS() throws {
        let settings = try #require(LiveGatewayTLSTrustInstaller.trustSettings.first)
        // Absent a policy the leaf would be trusted for code signing and
        // S/MIME too, where it only ever serves TLS on the loopback.
        #expect(settings[kSecTrustSettingsPolicy as String] != nil)
    }
}

@Suite("Gateway TLS trust diagnostics")
struct GatewayTLSTrustDiagnosticsTests {
    @Test("A refused install names the call and keeps the status")
    func installFailureCarriesStatus() {
        // The bridging bug answered errSecParam on the first attempt and
        // stayed invisible for as long as the status was dropped: the
        // number is the whole diagnosis, so it has to reach the log.
        let described = GatewayTLSTrustFailure.trustInstallFailed(errSecParam).description
        #expect(described.contains("-50"))
        #expect(described.contains("trusting the anchor failed"))
    }

    @Test("Each Security.framework call is distinguishable in the log")
    func failuresNameTheirCall() {
        let descriptions = [
            GatewayTLSTrustFailure.keychainImportFailed(errSecParam),
            .trustInstallFailed(errSecParam),
            .trustRevokeFailed(errSecParam),
            .trustStoreUnreadable(errSecParam),
        ].map(\.description)
        // Four calls that fail the same way have to read differently, or
        // the status alone cannot say which one refused.
        #expect(Set(descriptions).count == descriptions.count)
        #expect(descriptions.allSatisfy { $0.contains("-50") })
    }

    @Test("A dismissed prompt is not reported as a framework failure")
    func dismissedPromptHasItsOwnCase() {
        // The install can report success and still leave nothing behind;
        // saying so is not the same as saying a call returned an error.
        let described = GatewayTLSTrustFailure.anchorMissingAfterInstall.description
        #expect(described.contains("absent from the trust store"))
        #expect(!described.contains("OSStatus"))
    }

    @Test("A certificate that does not decode is refused before the keychain")
    func unreadableCertificateThrows() {
        let installer = LiveGatewayTLSTrustInstaller()
        #expect(throws: GatewayTLSTrustFailure.unreadableCertificate) {
            try installer.installTrust(certificatePEM: "not a certificate")
        }
        // The read path used to answer `false` here, which is the same
        // answer as a certificate that is simply not trusted yet.
        #expect(throws: GatewayTLSTrustFailure.unreadableCertificate) {
            _ = try installer.isTrusted(certificatePEM: "not a certificate")
        }
        #expect(throws: GatewayTLSTrustFailure.unreadableCertificate) {
            try installer.revokeTrust(certificatePEM: "not a certificate")
        }
    }

    @Test("Leftover clutter does not withhold the https profile")
    func failuresDoNotOverrideTheVerdict() {
        // A previous anchor that refuses to go is worth logging and is not
        // worth downgrading the connection over.
        let outcome = GatewayTLSTrustOutcome(
            isTrusted: true,
            failures: [.trustRevokeFailed(errSecParam)]
        )
        #expect(outcome.isTrusted)
        #expect(outcome.failures.count == 1)
    }

    @Test("An outcome with nothing to report carries no failures")
    func trustedOutcomeIsQuiet() {
        #expect(GatewayTLSTrustOutcome(isTrusted: true).failures.isEmpty)
    }
}
