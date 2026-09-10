import Foundation
import Security
import Testing
import X509

@testable import LittleSwitchCore

@Suite("Monitoring TLS identity compliance")
struct MonitoringTLSIdentityValidationTests {
    @Test(
        "Apple's TLS policy checks the hostname even with an in-memory trusted authority",
        arguments: ["localhost", "wrong-hostname.invalid"]
    )
    func appleTLSPolicy(hostname: String) throws {
        let issued = try GatewayTLSIdentityFactory.make()
        let leaf = try Certificate(pemEncoded: issued.certificatePEM)
        let validity = leaf.notValidAfter.timeIntervalSince(leaf.notValidBefore)
        #expect(validity <= TimeInterval(GatewayTLSIdentityFactory.validityDays * 86_400))
        let identity = try GatewayTLSIdentity(
            certificatePEM: issued.certificatePEM,
            authorityPEM: issued.authorityPEM,
            keyPEM: issued.keyPEM
        )
        let certificate = try #require(
            SecCertificateCreateWithData(nil, Data(try identity.certificate.toDERBytes()) as CFData)
        )
        let authority = try #require(
            SecCertificateCreateWithData(nil, Data(try identity.authority.toDERBytes()) as CFData)
        )
        var trust: SecTrust?
        #expect(
            SecTrustCreateWithCertificates(
                [certificate] as CFArray, SecPolicyCreateSSL(true, hostname as CFString), &trust) == errSecSuccess)
        let evaluation = try #require(trust)
        #expect(SecTrustSetAnchorCertificates(evaluation, [authority] as CFArray) == errSecSuccess)
        #expect(SecTrustSetAnchorCertificatesOnly(evaluation, true) == errSecSuccess)
        #expect(SecTrustSetNetworkFetchAllowed(evaluation, false) == errSecSuccess)
        var failure: CFError?
        let valid = SecTrustEvaluateWithError(evaluation, &failure)
        #expect(valid == (hostname == "localhost"))
        #expect((failure == nil) == (hostname == "localhost"))
    }
}
