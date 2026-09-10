import Crypto
import Foundation
import NIOSSL
import SwiftASN1
import X509

/// The gateway's TLS identity: a loopback leaf and the private authority
/// that issued it, served as one chain on the shared listener next to plain
/// HTTP.
///
/// The chain exists because a self-signed leaf is refused outright. Node —
/// which Claude Desktop's client is built on — answers
/// `DEPTH_ZERO_SELF_SIGNED_CERT` when the server certificate signs itself,
/// and installing that certificate as an anchor does not change it:
/// measured, the leaf reached Desktop's `ca-bundle.pem` (122 certificates)
/// and the connection was still refused with "Self-signed certificate
/// detected".
///
/// What keeps an installed authority from being a standing forgery
/// capability is that **its private key is never stored**. It is created in
/// memory, signs this one leaf, and is gone before `make` returns — it is
/// not even part of what `make` hands back, so no caller can persist it by
/// accident. An authority whose key no longer exists cannot issue anything
/// else, so the anchor is a marker for one frozen chain rather than a power
/// sitting on the user's disk.
public struct GatewayTLSIdentity: Sendable {
    public let certificate: NIOSSLCertificate
    /// The issuer of `certificate`. This is what the trust store anchors —
    /// never the leaf, which no longer validates on its own.
    public let authority: NIOSSLCertificate
    public let privateKey: NIOSSLPrivateKey
    /// The leaf PEM, persisted next to the key so restarts reuse one stable
    /// identity.
    public let certificatePEM: String
    /// The authority PEM, handed to the trust installer.
    public let authorityPEM: String

    public init(certificatePEM: String, authorityPEM: String, keyPEM: String) throws {
        self.certificatePEM = certificatePEM
        self.authorityPEM = authorityPEM
        self.certificate = try NIOSSLCertificate(
            bytes: Array(certificatePEM.utf8),
            format: .pem
        )
        self.authority = try NIOSSLCertificate(
            bytes: Array(authorityPEM.utf8),
            format: .pem
        )
        self.privateKey = try NIOSSLPrivateKey(
            bytes: Array(keyPEM.utf8),
            format: .pem
        )
    }

    package var tlsConfiguration: TLSConfiguration {
        var configuration = TLSConfiguration.makeServerConfiguration(
            // Leaf first, its issuer behind it: the handshake carries the
            // whole chain, so a client holding only the anchor can still
            // build the path.
            certificateChain: [.certificate(certificate), .certificate(authority)],
            privateKey: .privateKey(privateKey)
        )
        configuration.certificateVerification = .none
        return configuration
    }
}

/// Issues the pair in memory: a private authority and the loopback leaf it
/// signs, both P-256, with a validity window macOS honors for user-trusted
/// certificates. Only the leaf's key leaves this type, for the SecretStore;
/// no key ever reaches a plain file.
package enum GatewayTLSIdentityFactory {
    package static let validityDays = 825
    package static let renewalMarginDays = 30

    /// What the anchor is called in Keychain Access, and the only handle
    /// anything has on it.
    ///
    /// The certificate has to carry its own identity because the keychain
    /// will not carry one for it: adding an item with `kSecValueRef` makes
    /// the keychain derive the attributes from the certificate, and the
    /// derived `kSecAttrLabel` overrides whatever the caller passed. Apple
    /// documents `kSecAttrApplicationTag`, the usual alternative, as
    /// supported for key items only — the macOS shim silently ignores it on
    /// a certificate rather than failing, which turns a later lookup into
    /// "the first certificate found". So the subject is the metadata.
    package static let authorityCommonName = "\(ProductIdentity.displayName) loopback authority"

    /// A fresh issuance, before anything has been written down. The three
    /// artifacts land in three different places — two files and the
    /// Keychain — so they travel together until the store splits them.
    ///
    /// The authority's private key is deliberately absent. It exists inside
    /// `make` and nowhere else, so persisting it is not a discipline the
    /// callers have to keep — it is unreachable.
    package struct Issued: Sendable {
        package let certificatePEM: String
        package let authorityPEM: String
        package let keyPEM: String
    }

    package static func make(now: Date = Date()) throws -> Issued {
        let notValidBefore = now.addingTimeInterval(-TimeInterval(24 * 60 * 60))
        // The backdating margin is part of the validity period Apple limits to 825 days.
        let notValidAfter = notValidBefore.addingTimeInterval(
            TimeInterval(validityDays * 24 * 60 * 60)
        )

        let authorityKey = P256.Signing.PrivateKey()
        let authorityPrivateKey = Certificate.PrivateKey(authorityKey)
        let authorityPublicKey = Certificate.PublicKey(authorityKey.publicKey)
        let authorityName = try DistinguishedName {
            CommonName(authorityCommonName)
            OrganizationName(ProductIdentity.displayName)
        }
        // RFC 5280 §4.2.1.2: a conforming CA's subject key identifier is the
        // value its issued certificates carry as authority key identifier,
        // so both certificates are built from this one.
        let authorityIdentifier = SubjectKeyIdentifier(hash: authorityPublicKey)
        let authority = try Certificate(
            version: .v3,
            serialNumber: serialNumber(),
            publicKey: authorityPublicKey,
            notValidBefore: notValidBefore,
            notValidAfter: notValidAfter,
            issuer: authorityName,
            subject: authorityName,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try authorityExtensions(identifier: authorityIdentifier),
            issuerPrivateKey: authorityPrivateKey
        )

        let leafKey = P256.Signing.PrivateKey()
        let leafPublicKey = Certificate.PublicKey(leafKey.publicKey)
        // `localhost` is what a human reads on the certificate; the
        // organization is what separates it from every other loopback leaf
        // on the machine, in Keychain Access and in a subject search alike.
        // Hostname validation ignores both and reads the SAN.
        let leafName = try DistinguishedName {
            CommonName("localhost")
            OrganizationName(ProductIdentity.displayName)
        }
        let leaf = try Certificate(
            version: .v3,
            serialNumber: serialNumber(),
            publicKey: leafPublicKey,
            notValidBefore: notValidBefore,
            notValidAfter: notValidAfter,
            issuer: authorityName,
            subject: leafName,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try leafExtensions(
                publicKey: leafPublicKey,
                authority: authorityIdentifier
            ),
            issuerPrivateKey: authorityPrivateKey
        )

        return Issued(
            certificatePEM: try leaf.serializeAsPEM().pemString,
            authorityPEM: try authority.serializeAsPEM().pemString,
            keyPEM: try Certificate.PrivateKey(leafKey).serializeAsPEM().pemString
        )
    }

    private static func serialNumber() -> Certificate.SerialNumber {
        Certificate.SerialNumber(
            bytes: (0..<16).map { _ in UInt8.random(in: .min ... .max) }
        )
    }

    /// The authority carries the one extension that makes a chain verify:
    /// without `BasicConstraints` naming it a CA, a validator refuses it as
    /// an issuer. `maxPathLength: 0` forbids it from ever anchoring an
    /// intermediate, which its destroyed key already makes impossible.
    ///
    /// RFC 5280 requires both `BasicConstraints` (§4.2.1.9) and `KeyUsage`
    /// (§4.2.1.3) to be marked critical here, so that a validator which
    /// cannot read them refuses the certificate rather than trusting it for
    /// more than it says. The subject key identifier (§4.2.1.2) MUST appear
    /// in a CA certificate: it is the link the leaf points back at.
    private static func authorityExtensions(
        identifier: SubjectKeyIdentifier
    ) throws -> Certificate.Extensions {
        try Certificate.Extensions {
            Critical(
                BasicConstraints.isCertificateAuthority(maxPathLength: 0)
            )
            Critical(
                KeyUsage(keyCertSign: true)
            )
            identifier
        }
    }

    /// The leaf carries no `BasicConstraints` at all: absent, it is not a
    /// certificate authority, which is what an end-entity certificate must
    /// be.
    ///
    /// `digitalSignature` is the bit an ECDSA server certificate needs — the
    /// server signs the handshake rather than having a key transported to
    /// it — and RFC 5280 §4.2.1.3 wants the extension marked critical when
    /// present. The authority key identifier (§4.2.1.1) names the issuer by
    /// key rather than by name, which is what lets a validator follow the
    /// link instead of trying every candidate issuer it holds.
    private static func leafExtensions(
        publicKey: Certificate.PublicKey,
        authority: SubjectKeyIdentifier
    ) throws -> Certificate.Extensions {
        let names = SubjectAlternativeNames([
            .dnsName("localhost"),
            .ipAddress(ASN1OctetString(contentBytes: [127, 0, 0, 1])),
        ])
        return try Certificate.Extensions {
            names
            Critical(
                KeyUsage(digitalSignature: true)
            )
            try ExtendedKeyUsage([.serverAuth])
            SubjectKeyIdentifier(hash: publicKey)
            AuthorityKeyIdentifier(keyIdentifier: authority.keyIdentifier)
        }
    }

    /// Whether a stored triple can actually serve a handshake.
    ///
    /// Presence and expiry are not enough to reuse one. The three artifacts
    /// live in three places — two files and the Keychain — and nothing
    /// makes those writes one transaction. A crash between them, a disk
    /// that fills mid-issuance, or a Keychain restored from another machine
    /// all leave a set that parses cleanly and then fails at every
    /// handshake. The store only asked whether the files existed, so it
    /// would hand that set back for the life of the machine.
    ///
    /// Two things are checked, because they fail differently. A key that
    /// does not match its certificate is refused by BoringSSL when the
    /// context is built — which is the listener's own first step, so a
    /// stored triple that fails here takes the whole gateway down at
    /// startup, http included, not just the TLS half. A leaf and an
    /// authority that no longer belong to each other build a context
    /// happily and then serve a chain no client can verify: same subject on
    /// every authority we issue, so only the signature separates them.
    package static func isServable(_ identity: GatewayTLSIdentity) -> Bool {
        guard
            let leaf = try? Certificate(pemEncoded: identity.certificatePEM),
            let authority = try? Certificate(pemEncoded: identity.authorityPEM),
            authority.publicKey.isValidSignature(leaf.signature, for: leaf),
            (try? NIOSSLContext(configuration: identity.tlsConfiguration)) != nil
        else {
            return false
        }
        return true
    }

    /// The remaining lifetime an existing leaf must have before it is
    /// reissued: below the margin the search would keep working until, one
    /// day, it fails silently everywhere at once.
    package static func isRenewalDue(certificatePEM: String, now: Date = Date()) -> Bool {
        guard let certificate = try? Certificate(pemEncoded: certificatePEM) else {
            return true
        }
        let margin = TimeInterval(renewalMarginDays * 24 * 60 * 60)
        return certificate.notValidAfter.timeIntervalSince(now) < margin
    }
}

/// Loads, provisions, and persists the identity. The certificate is public
/// data on disk; the private key lives in the SecretStore. It also keeps the
/// ledger of anchors a reissue replaced, which has to outlive the call that
/// replaced them.
package struct GatewayTLSIdentityStore: Sendable {
    package let directory: URL
    package let secretStore: any SecretStore

    package init(directory: URL, secretStore: any SecretStore) {
        self.directory = directory
        self.secretStore = secretStore
    }

    package static func liveDirectory(
        applicationSupport: URL = URL(
            fileURLWithPath: NSHomeDirectory(),
            isDirectory: true
        )
        .appending(path: "Library/Application Support", directoryHint: .isDirectory)
    ) -> URL {
        applicationSupport
            .appending(
                path: ProductIdentity.applicationSupportDirectoryName,
                directoryHint: .isDirectory
            )
            .appending(path: "TLS", directoryHint: .isDirectory)
    }

    private var certificateURL: URL {
        directory.appending(path: "leaf.pem")
    }

    private var authorityURL: URL {
        directory.appending(path: "authority.pem")
    }

    private var supersededURL: URL {
        directory.appending(path: "superseded.pem")
    }

    /// The certificate this machine trusts on our behalf, read without
    /// provisioning anything: the authority, or — for an identity issued
    /// before the chain existed — the leaf that was the anchor in its day.
    ///
    /// Asking whether the anchor is trusted, or removing it, must not be
    /// able to replace the anchor being asked about. `ensure` writes, so a
    /// read-shaped caller that routes through it can mint a new identity in
    /// the middle of the question and answer about the wrong certificate.
    package var installedAnchorPEM: String? {
        (try? String(contentsOf: authorityURL, encoding: .utf8))
            ?? (try? String(contentsOf: certificateURL, encoding: .utf8))
    }

    /// Anchors a reissue replaced that are still trusted on this machine.
    ///
    /// Whoever provisions is rarely whoever revokes: `ensure` is reached
    /// first by the listener's identity at gateway start, long before the
    /// trust install runs, so handing the replaced anchor back as a return
    /// value loses it — the install that follows sees a reusable identity
    /// and nothing to purge. Written down here it survives that gap.
    package var supersededAnchorPEMs: [String] {
        guard let contents = try? String(contentsOf: supersededURL, encoding: .utf8) else {
            return []
        }
        return Self.pemBlocks(in: contents)
    }

    /// Replaces the ledger with the anchors still to purge. An entry leaves
    /// only once its anchor is gone from the trust store, so a removal that
    /// fails is retried on the next connect rather than forgotten.
    package func retainSuperseded(_ pems: [String]) throws {
        guard !pems.isEmpty else {
            if FileManager.default.fileExists(atPath: supersededURL.path) {
                try FileManager.default.removeItem(at: supersededURL)
            }
            return
        }
        let normalized = pems.map { $0.hasSuffix("\n") ? $0 : $0 + "\n" }
        try AtomicFileWriter.write(
            Data(normalized.joined().utf8),
            to: supersededURL,
            backupDirectory: directory,
            backupLimit: 0
        )
    }

    /// Splits concatenated PEM certificates back apart. The ledger holds one
    /// block per anchor and the trust installer takes them one at a time.
    ///
    /// Blocks come back without a trailing newline, the shape
    /// `serializeAsPEM` produces and the shape the certificate files hold,
    /// so a ledger entry compares equal to the anchor it was read from.
    private static func pemBlocks(in contents: String) -> [String] {
        var blocks: [String] = []
        var current: [Substring] = []
        for line in contents.split(separator: "\n") {
            current.append(line)
            guard line.contains("END CERTIFICATE") else {
                continue
            }
            blocks.append(current.joined(separator: "\n"))
            current = []
        }
        return blocks
    }

    /// Returns a non-expiring identity, reissuing it when either stored
    /// certificate is missing or the leaf is inside the renewal margin. A
    /// reissue records the anchor it replaced so its trust settings can be
    /// purged instead of accumulating.
    package func ensure(now: Date = Date()) throws -> GatewayTLSIdentity {
        let storedKey = try secretStore.read(account: .gatewayTLS)
        if let storedKey, let reusable = try reusableIdentity(storedKey: storedKey, now: now) {
            return reusable
        }
        // The anchor about to be overwritten is still trusted on this
        // machine. An identity stored before the chain existed has a leaf
        // and no authority, and that leaf is what its install trusted:
        // without the fallback every install from that era keeps a trusted
        // `localhost` leaf for the life of the machine.
        let superseded = installedAnchorPEM
        let issued = try GatewayTLSIdentityFactory.make(now: now)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try AtomicFileWriter.write(
            Data(issued.certificatePEM.utf8),
            to: certificateURL,
            backupDirectory: directory
        )
        try AtomicFileWriter.write(
            Data(issued.authorityPEM.utf8),
            to: authorityURL,
            backupDirectory: directory
        )
        try secretStore.write(issued.keyPEM, account: .gatewayTLS)
        if let superseded, !supersededAnchorPEMs.contains(superseded) {
            try retainSuperseded(supersededAnchorPEMs + [superseded])
        }
        return try GatewayTLSIdentity(
            certificatePEM: issued.certificatePEM,
            authorityPEM: issued.authorityPEM,
            keyPEM: issued.keyPEM
        )
    }

    private func reusableIdentity(
        storedKey: String,
        now: Date
    ) throws -> GatewayTLSIdentity? {
        guard
            let certificatePEM = try? String(
                contentsOf: certificateURL,
                encoding: .utf8
            ),
            // A leaf without its authority cannot serve a chain any client
            // will accept, so a half-written state reissues rather than
            // starting the listener on something already broken.
            let authorityPEM = try? String(
                contentsOf: authorityURL,
                encoding: .utf8
            ),
            !GatewayTLSIdentityFactory.isRenewalDue(
                certificatePEM: certificatePEM,
                now: now
            ),
            let identity = try? GatewayTLSIdentity(
                certificatePEM: certificatePEM,
                authorityPEM: authorityPEM,
                keyPEM: storedKey
            ),
            // Reissuing is always available and always works; keeping a set
            // that cannot serve is the only outcome with no way back.
            GatewayTLSIdentityFactory.isServable(identity)
        else {
            return nil
        }
        return identity
    }

}
