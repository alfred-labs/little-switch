import Crypto
import Foundation
import HummingbirdCore
import Logging
import NIOCore
import NIOEmbedded
import Testing
import X509

@testable import LittleSwitchCore

@Suite("Gateway TLS identity")
struct GatewayTLSIdentityTests {
    @Test("The issued leaf is authority-signed, loopback-bound, and long-lived")
    func issuedLeafShape() throws {
        let issued = try GatewayTLSIdentityFactory.make()

        let certificate = try Certificate(pemEncoded: issued.certificatePEM)
        let authority = try Certificate(pemEncoded: issued.authorityPEM)
        // A leaf that signs itself is what Node refuses outright, anchor or
        // no anchor: its issuer has to be someone else.
        #expect(certificate.issuer != certificate.subject)
        #expect(certificate.issuer == authority.subject)
        #expect(authority.issuer == authority.subject)
        let san = try #require(
            try certificate.extensions.subjectAlternativeNames
        )
        let names = san.map(\.description).joined()
        #expect(names.contains("DNSName"))
        #expect(names.contains("localhost"))
        #expect(names.contains("IPAddress([127, 0, 0, 1])"))

        let identity = try GatewayTLSIdentity(
            certificatePEM: issued.certificatePEM,
            authorityPEM: issued.authorityPEM,
            keyPEM: issued.keyPEM
        )
        _ = identity.tlsConfiguration
    }

    @Test("Only the authority is a certificate authority")
    func authorityConstraints() throws {
        let issued = try GatewayTLSIdentityFactory.make()

        let authority = try Certificate(pemEncoded: issued.authorityPEM)
        let constraints = try #require(try authority.extensions.basicConstraints)
        #expect(constraints == .isCertificateAuthority(maxPathLength: 0))

        // Absent BasicConstraints the leaf is an end entity, which is what
        // it must be — and it is not what the trust store anchors either.
        let certificate = try Certificate(pemEncoded: issued.certificatePEM)
        #expect(try certificate.extensions.basicConstraints == nil)
    }

    @Test("The chain carries the identifiers and constraints RFC 5280 asks for")
    func chainMetadata() throws {
        let issued = try GatewayTLSIdentityFactory.make()
        let authority = try Certificate(pemEncoded: issued.authorityPEM)
        let certificate = try Certificate(pemEncoded: issued.certificatePEM)

        // §4.2.1.9 and §4.2.1.3: marked critical, a validator that cannot
        // read either one refuses the certificate instead of trusting it
        // for more than it claims.
        let constraints = try #require(
            authority.extensions.first { $0.oid == .X509ExtensionID.basicConstraints }
        )
        #expect(constraints.critical)
        let authorityUsageExtension = try #require(
            authority.extensions.first { $0.oid == .X509ExtensionID.keyUsage }
        )
        #expect(authorityUsageExtension.critical)
        let authorityUsage = try KeyUsage(authorityUsageExtension)
        #expect(authorityUsage.keyCertSign)

        // §4.2.1.2 and §4.2.1.1: the leaf names its issuer by key, and the
        // value it names is the authority's own subject key identifier —
        // the link a validator follows instead of trying every candidate
        // issuer it holds.
        let subjectKeyIDExtension = try #require(
            authority.extensions.first { $0.oid == .X509ExtensionID.subjectKeyIdentifier }
        )
        let authorityKeyIDExtension = try #require(
            certificate.extensions.first { $0.oid == .X509ExtensionID.authorityKeyIdentifier }
        )
        let subjectKeyID = try SubjectKeyIdentifier(subjectKeyIDExtension)
        let authorityKeyID = try AuthorityKeyIdentifier(authorityKeyIDExtension)
        #expect(authorityKeyID.keyIdentifier == subjectKeyID.keyIdentifier)

        // An ECDSA server certificate signs the handshake rather than having
        // a key transported to it, so `digitalSignature` is the bit it
        // needs — and it must not be able to sign certificates.
        let leafUsageExtension = try #require(
            certificate.extensions.first { $0.oid == .X509ExtensionID.keyUsage }
        )
        #expect(leafUsageExtension.critical)
        let leafUsage = try KeyUsage(leafUsageExtension)
        #expect(leafUsage.digitalSignature)
        #expect(!leafUsage.keyCertSign)
    }

    @Test("Both certificates name the product that issued them")
    func subjectsAreIdentifiable() throws {
        let issued = try GatewayTLSIdentityFactory.make()
        let authority = try Certificate(pemEncoded: issued.authorityPEM)
        let certificate = try Certificate(pemEncoded: issued.certificatePEM)

        // Adding a certificate to the keychain derives its label from the
        // certificate and discards the one the caller passes, and the
        // attribute usually reached for instead is documented as key-only.
        // The subject is therefore the only metadata that survives: it is
        // what Keychain Access shows and what a later sweep can match.
        #expect(
            authority.subject.description.contains(
                GatewayTLSIdentityFactory.authorityCommonName
            )
        )
        #expect(authority.subject.description.contains(ProductIdentity.displayName))
        #expect(certificate.subject.description.contains(ProductIdentity.displayName))
        // The leaf keeps the conventional common name a human reads; only
        // the SAN decides which hosts it is valid for.
        #expect(certificate.subject.description.contains("localhost"))
    }

    @Test("Issuance hands back the leaf's key and never the authority's")
    func authorityKeyIsUnreachable() throws {
        let issued = try GatewayTLSIdentityFactory.make()

        // The invariant the design rests on: anchoring an authority on a
        // user's machine is acceptable only because the key that could sign
        // under it no longer exists anywhere. Issuance returns exactly one
        // key and it is the leaf's — the authority's is not a field of the
        // result, so no caller can persist it by accident.
        let certificate = try Certificate(pemEncoded: issued.certificatePEM)
        let authority = try Certificate(pemEncoded: issued.authorityPEM)
        #expect(certificate.publicKey != authority.publicKey)
        // The returned key pairs with the leaf: this is the construction the
        // listener performs, and it is the only one issuance supports.
        _ = try GatewayTLSIdentity(
            certificatePEM: issued.certificatePEM,
            authorityPEM: issued.authorityPEM,
            keyPEM: issued.keyPEM
        )
    }

    @Test("A set that cannot serve a handshake is not servable")
    func servabilityRejectsBrokenSets() throws {
        let issued = try GatewayTLSIdentityFactory.make()
        let other = try GatewayTLSIdentityFactory.make()

        let sound = try GatewayTLSIdentity(
            certificatePEM: issued.certificatePEM,
            authorityPEM: issued.authorityPEM,
            keyPEM: issued.keyPEM
        )
        #expect(GatewayTLSIdentityFactory.isServable(sound))

        // A key from another issuance parses cleanly and is refused by
        // BoringSSL when the listener builds its context — which is the
        // gateway's first step, so this set takes down http along with TLS.
        let mismatchedKey = try GatewayTLSIdentity(
            certificatePEM: issued.certificatePEM,
            authorityPEM: issued.authorityPEM,
            keyPEM: other.keyPEM
        )
        #expect(!GatewayTLSIdentityFactory.isServable(mismatchedKey))

        // Every authority we issue carries the same subject, so a name
        // comparison would accept this one. Only the signature separates it
        // from the certificate that actually signed the leaf.
        let foreignAuthority = try GatewayTLSIdentity(
            certificatePEM: issued.certificatePEM,
            authorityPEM: other.authorityPEM,
            keyPEM: issued.keyPEM
        )
        #expect(!GatewayTLSIdentityFactory.isServable(foreignAuthority))
    }

    @Test("Renewal is due for garbage, expiry, and margin — not fresh leaves")
    func renewalMargin() throws {
        let issued = try GatewayTLSIdentityFactory.make()
        #expect(
            !GatewayTLSIdentityFactory.isRenewalDue(certificatePEM: issued.certificatePEM)
        )
        #expect(
            GatewayTLSIdentityFactory.isRenewalDue(certificatePEM: "not a certificate")
        )
        let stale = try GatewayTLSIdentityFactory.make(
            now: Date().addingTimeInterval(-TimeInterval(800 * 24 * 60 * 60))
        )
        #expect(
            GatewayTLSIdentityFactory.isRenewalDue(certificatePEM: stale.certificatePEM)
        )
    }

    @Test("The store reuses the stored identity and reissues on renewal")
    func storeLifecycle() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "little-switch-tls-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GatewayTLSIdentityStore(
            directory: directory,
            secretStore: MemorySecretStore()
        )

        let first = try store.ensure()
        // A first issuance replaces nothing, so there is nothing to purge.
        #expect(store.supersededAnchorPEMs.isEmpty)
        #expect(store.installedAnchorPEM == first.authorityPEM)
        let second = try store.ensure()
        #expect(store.supersededAnchorPEMs.isEmpty)
        #expect(second.certificatePEM == first.certificatePEM)
        #expect(
            FileManager.default.fileExists(
                atPath: directory.appending(path: "leaf.pem").path
            )
        )

        let key = try store.secretStore.read(account: .gatewayTLS)
        try store.secretStore.delete(account: .gatewayTLS)
        _ = key
        let third = try store.ensure()
        #expect(third.certificatePEM != first.certificatePEM)
        // The anchor the reissue replaced is still trusted on the machine,
        // and the caller that reissued is rarely the one that revokes.
        #expect(store.supersededAnchorPEMs == [first.authorityPEM])
        #expect(store.installedAnchorPEM == third.authorityPEM)

        // A kept key with a missing certificate file is not reusable.
        try FileManager.default.removeItem(
            at: directory.appending(path: "leaf.pem")
        )
        let fourth = try store.ensure()
        #expect(fourth.certificatePEM != third.certificatePEM)
        #expect(
            store.supersededAnchorPEMs == [first.authorityPEM, third.authorityPEM]
        )
    }

    @Test("A stored key that no longer matches its certificate reissues")
    func brokenStoredSetReissues() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "little-switch-tls-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GatewayTLSIdentityStore(
            directory: directory,
            secretStore: MemorySecretStore()
        )

        let first = try store.ensure()
        // What a crash between the certificate writes and the Keychain
        // write leaves behind — and what a Keychain restored from another
        // machine looks like. It parses, so presence and expiry both say
        // "reusable", and every handshake fails until someone deletes the
        // folder by hand.
        let foreign = try GatewayTLSIdentityFactory.make()
        try store.secretStore.write(foreign.keyPEM, account: .gatewayTLS)

        let second = try store.ensure()
        #expect(second.certificatePEM != first.certificatePEM)
        #expect(GatewayTLSIdentityFactory.isServable(second))
    }

    @Test("The ledger clears only once its anchors are gone")
    func supersededLedgerLifecycle() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "little-switch-tls-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GatewayTLSIdentityStore(
            directory: directory,
            secretStore: MemorySecretStore()
        )

        // Clearing an absent ledger is the ordinary case: every connect
        // clears it, and most machines never had one.
        try store.retainSuperseded([])
        #expect(store.supersededAnchorPEMs.isEmpty)

        let issued = try GatewayTLSIdentityFactory.make()
        try store.retainSuperseded([issued.authorityPEM, issued.certificatePEM])
        #expect(
            store.supersededAnchorPEMs == [issued.authorityPEM, issued.certificatePEM]
        )

        // A removal that failed keeps its entry; the ones that worked leave.
        try store.retainSuperseded([issued.certificatePEM])
        #expect(store.supersededAnchorPEMs == [issued.certificatePEM])

        try store.retainSuperseded([])
        #expect(store.supersededAnchorPEMs.isEmpty)
    }

    @Test("The anchor is read without provisioning anything")
    func installedAnchorReadsWithoutWriting() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "little-switch-tls-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GatewayTLSIdentityStore(
            directory: directory,
            secretStore: MemorySecretStore()
        )

        // Nothing on disk answers "no anchor" rather than minting one.
        #expect(store.installedAnchorPEM == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path))

        let identity = try store.ensure()
        #expect(store.installedAnchorPEM == identity.authorityPEM)

        // An identity issued before the chain existed has a leaf and no
        // authority, and that leaf is the certificate its install trusted.
        try FileManager.default.removeItem(
            at: directory.appending(path: "authority.pem")
        )
        #expect(store.installedAnchorPEM == identity.certificatePEM)
    }

    @Test("The live directory nests under the app support folder")
    func liveDirectoryShape() {
        let root = URL(fileURLWithPath: "/tmp/little-switch-tls-root")
        let directory = GatewayTLSIdentityStore.liveDirectory(applicationSupport: root)
        #expect(
            directory.path
                == "/tmp/little-switch-tls-root/\(ProductIdentity.applicationSupportDirectoryName)/TLS"
        )
    }
}

/// A value the sniffing setup can resolve without any HTTP machinery.
private struct ProbeValue: ServerChildChannelValue {
    let channel: any Channel
}

@Suite("Dual-protocol listener")
struct DualProtocolServerTests {
    private func makeSniffer(
        decided: @escaping @Sendable (Result<String, any Error>) -> Void
    ) throws -> ProtocolSniffHandler<String> {
        ProtocolSniffHandler<String>(
            plainSetup: { _, _ in
                decided(.success("plain"))
                return EmbeddedEventLoop().makeSucceededFuture("plain")
            },
            secureSetup: { _, _ in
                decided(.success("secure"))
                return EmbeddedEventLoop().makeSucceededFuture("secure")
            },
            completion: { _ in },
            logger: Logger(label: "test")
        )
    }

    private func installSniffer(
        on channel: EmbeddedChannel,
        decided: @escaping @Sendable (Result<String, any Error>) -> Void
    ) throws {
        let sniffer = try makeSniffer(decided: decided)
        try channel.pipeline.syncOperations.addHandler(sniffer)
    }

    @Test("A TLS ClientHello selects the secure setup")
    func selectsTLS() throws {
        let channel = EmbeddedChannel()
        try installSniffer(on: channel) { result in
            #expect((try? result.get()) == "secure")
        }
        channel.pipeline.fireChannelRead(
            ByteBuffer(bytes: [0x16, 0x03, 0x01, 0x00, 0x50])
        )
        _ = try? channel.finish()
    }

    @Test("Anything else selects the plain setup")
    func selectsPlain() throws {
        let channel = EmbeddedChannel()
        try installSniffer(on: channel) { result in
            #expect((try? result.get()) == "plain")
        }
        channel.pipeline.fireChannelRead(
            ByteBuffer(string: "GET / HTTP/1.1\r\n")
        )
        _ = try? channel.finish()
    }

    @Test("Zero-length reads wait for the deciding byte")
    func waitsForBytes() throws {
        let channel = EmbeddedChannel()
        try installSniffer(on: channel) { result in
            #expect((try? result.get()) == "plain")
        }
        channel.pipeline.fireChannelRead(ByteBuffer(bytes: []))
        channel.pipeline.fireChannelRead(ByteBuffer(bytes: [0x47]))
        _ = try? channel.finish()
    }

    @Test("After the decision, bytes pass through untouched")
    func passesThroughAfterDecision() throws {
        let channel = EmbeddedChannel()
        try installSniffer(on: channel) { _ in }
        let first = ByteBuffer(string: "GET / HTTP/1.1\r\nHost: x\r\n\r\n")
        channel.pipeline.fireChannelRead(first)
        // The sniffer must not consume or modify the buffer.
        let passthrough: ByteBuffer? = try channel.readInbound()
        #expect(passthrough == first)
        channel.pipeline.fireChannelRead(ByteBuffer(string: "more bytes"))
        _ = try? channel.finish()
    }
}
