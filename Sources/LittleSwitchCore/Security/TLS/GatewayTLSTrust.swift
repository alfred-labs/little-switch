import Foundation
import Security

/// Why a trust operation did not land. Every case that can carry an
/// `OSStatus` carries it: these are the values Security.framework answers
/// synchronously, and losing them is what made a `-50` — a bridging bug in
/// the settings dictionary, visible in the very first call — look like a
/// silent refusal by the user for as long as it did.
public enum GatewayTLSTrustFailure: Swift.Error, Equatable, Sendable {
    /// No identity to anchor: the store could neither read nor issue one.
    case identityUnavailable
    /// The stored PEM does not decode into a certificate.
    case unreadableCertificate
    /// `SecItemAdd` refused the certificate. Trust settings are only
    /// consultable once the certificate itself is in the keychain.
    case keychainImportFailed(OSStatus)
    /// `SecTrustSettingsSetTrustSettings` refused the anchor.
    case trustInstallFailed(OSStatus)
    /// `SecTrustSettingsRemoveTrustSettings` or `SecItemDelete` refused.
    case trustRevokeFailed(OSStatus)
    /// The user trust store could not be enumerated, so whether the anchor
    /// is present is unknown — which is not the same as it being absent.
    case trustStoreUnreadable(OSStatus)
    /// The install reported success yet the anchor is not in the store:
    /// the consent prompt was dismissed, or it was written somewhere we do
    /// not read back.
    case anchorMissingAfterInstall
    /// The list of anchors still to purge could not be rewritten. The old
    /// list stands, so nothing pending is forgotten — an anchor already
    /// removed is simply attempted again on the next connect.
    case supersededLedgerUnwritable(String)
}

extension GatewayTLSTrustFailure: CustomStringConvertible {
    public var description: String {
        switch self {
        case .identityUnavailable:
            "the gateway TLS identity could not be read or issued"
        case .unreadableCertificate:
            "the stored certificate does not decode as DER"
        case .keychainImportFailed(let status):
            "importing the anchor into the keychain failed: \(Self.describe(status))"
        case .trustInstallFailed(let status):
            "trusting the anchor failed: \(Self.describe(status))"
        case .trustRevokeFailed(let status):
            "removing the anchor failed: \(Self.describe(status))"
        case .trustStoreUnreadable(let status):
            "reading the user trust store failed: \(Self.describe(status))"
        case .anchorMissingAfterInstall:
            "the anchor is absent from the trust store although the install succeeded"
        case .supersededLedgerUnwritable(let reason):
            "the list of anchors still to purge could not be written: \(reason)"
        }
    }

    /// The number alone identifies the call that refused; the framework's
    /// own message says what it objected to, which is the half that turns a
    /// log line into a diagnosis.
    private static func describe(_ status: OSStatus) -> String {
        guard let message = SecCopyErrorMessageString(status, nil) else {
            return "OSStatus \(status)"
        }
        return "OSStatus \(status) (\(message as String))"
    }
}

/// Where a trust attempt left the anchor, and everything that refused along
/// the way. `isTrusted` is the verdict the https profile gates on; a
/// failure recorded next to `isTrusted == true` is clutter left behind, not
/// a blocked connection.
public struct GatewayTLSTrustOutcome: Equatable, Sendable {
    public let isTrusted: Bool
    public let failures: [GatewayTLSTrustFailure]

    public init(isTrusted: Bool, failures: [GatewayTLSTrustFailure] = []) {
        self.isTrusted = isTrusted
        self.failures = failures
    }
}

package struct LiveGatewayTLSTrustInstaller {
    package init() {}

    package func isTrusted(certificatePEM: String) throws(GatewayTLSTrustFailure) -> Bool {
        guard let certificate = Self.secCertificate(pem: certificatePEM) else {
            throw GatewayTLSTrustFailure.unreadableCertificate
        }
        var settings: CFArray?
        let status = SecTrustSettingsCopyCertificates(
            SecTrustSettingsDomain.user,
            &settings
        )
        // An empty domain is the answer on a machine that has never
        // trusted anything of ours, not a read failure.
        if status == errSecNoTrustSettings {
            return false
        }
        guard status == errSecSuccess, let settings else {
            throw GatewayTLSTrustFailure.trustStoreUnreadable(status)
        }
        let anchors = settings as [AnyObject] as? [SecCertificate] ?? []
        let leaf = SecCertificateCopyData(certificate) as Data
        return anchors.contains { existing in
            SecCertificateCopyData(existing) as Data == leaf
        }
    }

    /// The certificate must be imported before its trust settings are
    /// consultable: this is the import step `security add-trusted-cert`
    /// performs before setting trust.
    package func installTrust(certificatePEM: String) throws(GatewayTLSTrustFailure) {
        guard let certificate = Self.secCertificate(pem: certificatePEM) else {
            throw GatewayTLSTrustFailure.unreadableCertificate
        }
        let importStatus = SecItemAdd(
            [
                kSecClass: kSecClassCertificate,
                kSecValueRef: certificate,
            ] as CFDictionary,
            nil
        )
        guard
            importStatus == errSecSuccess || importStatus == errSecDuplicateItem
        else {
            throw GatewayTLSTrustFailure.keychainImportFailed(importStatus)
        }
        if try !isTrusted(certificatePEM: certificatePEM) {
            let addStatus = SecTrustSettingsSetTrustSettings(
                certificate,
                SecTrustSettingsDomain.user,
                Self.trustSettings as CFArray
            )
            guard addStatus == errSecSuccess else {
                throw GatewayTLSTrustFailure.trustInstallFailed(addStatus)
            }
        }
    }

    /// What Security.framework accepts for the loopback anchor. Two details
    /// carry the whole call and both were wrong.
    ///
    /// `SecTrustSettingsResult` is a Swift enum over `UInt32`: handed to a
    /// `CFDictionary` as itself it does not bridge to the `CFNumber` the
    /// framework reads, and the call answers `errSecParam` (-50) without
    /// installing anything. Measured against this very certificate, the raw
    /// enum fails and `NSNumber(value:rawValue)` succeeds — nothing else
    /// about the call changes. `trustRoot` is the correct result for the
    /// self-signed authority; `trustAsRoot`, which reads like the choice for
    /// anything that is not a root, is what earns the -50.
    ///
    /// Without a policy the anchor would be trusted for every purpose —
    /// code signing and S/MIME included — where it only ever vouches for one
    /// loopback TLS certificate. `security add-trusted-cert -p ssl`, the
    /// command this path mirrors, restricts it the same way.
    package static var trustSettings: [[String: Any]] {
        [
            [
                kSecTrustSettingsResult as String: NSNumber(
                    value: SecTrustSettingsResult.trustRoot.rawValue
                ),
                kSecTrustSettingsPolicy as String: SecPolicyCreateSSL(true, nil),
            ]
        ]
    }

    package func revokeTrust(certificatePEM: String) throws(GatewayTLSTrustFailure) {
        guard let certificate = Self.secCertificate(pem: certificatePEM) else {
            throw GatewayTLSTrustFailure.unreadableCertificate
        }
        let removeStatus = SecTrustSettingsRemoveTrustSettings(
            certificate,
            SecTrustSettingsDomain.user
        )
        guard removeStatus == errSecSuccess || removeStatus == errSecItemNotFound else {
            throw GatewayTLSTrustFailure.trustRevokeFailed(removeStatus)
        }
        let deleteStatus = SecItemDelete(
            [
                kSecClass: kSecClassCertificate,
                kSecValueRef: certificate,
            ] as CFDictionary
        )
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw GatewayTLSTrustFailure.trustRevokeFailed(deleteStatus)
        }
    }

    /// Security.framework takes DER bytes; the identity is carried as PEM.
    private static func secCertificate(pem: String) -> SecCertificate? {
        let lines = pem.split(separator: "\n")
        let base64 =
            lines
            .drop { !$0.contains("BEGIN CERTIFICATE") }
            .dropFirst()
            .prefix { !$0.contains("END CERTIFICATE") }
            .joined()
        guard let der = Data(base64Encoded: base64) else {
            return nil
        }
        return SecCertificateCreateWithData(nil, der as CFData)
    }
}

/// Everything the coordinator needs from the gateway's TLS footprint:
/// producing the listener identity and (once, with the system's consent
/// prompt) trusting the anchor. Injected as a whole so tests run with no TLS
/// at all — no files under the real application support folder, no writes
/// against their choreographed secret stores, no keychain prompts — while
/// the live app wires the real provisioner at construction.
///
/// The trust calls report what refused rather than only whether they
/// worked: this module deliberately does not log, so a Security.framework
/// status is only diagnosable if it travels out to the coordinator, which
/// does.
public protocol GatewayTLSProvisioning: Sendable {
    func identity(secretStore: any SecretStore) -> GatewayTLSIdentity?
    /// Attempts the trust installation — raising the system's consent
    /// prompt when the authority is not trusted yet — and reports where the
    /// anchor stands once the attempt settles, with the failures behind it.
    /// The anchor is the authority, not the leaf: a self-signed leaf is
    /// refused by the client whatever the trust store says. Anchors a
    /// reissue replaced are purged here, wherever the reissue happened, so
    /// nothing accumulates.
    func installTrust(secretStore: any SecretStore) -> GatewayTLSTrustOutcome
    /// Whether the authority is already trusted. Never prompts, and never
    /// provisions: it reads the anchor on disk rather than asking for one,
    /// so a question about the trust state cannot mint the identity it is
    /// asking about. A trust store we cannot read answers `false`, which
    /// keeps the profile on plain http — the safe side of an unknown.
    func isTrusted(secretStore: any SecretStore) -> Bool
    /// Removes the trust anchor, its certificate, and anything a reissue
    /// left behind: the app leaves no footprint in the user's trust store
    /// once disconnected. Reads the anchor rather than provisioning one, for
    /// the same reason — a revoke that reissues first would remove a
    /// certificate nobody ever trusted and leave the real one in place.
    /// Returns what refused to go; empty means nothing is left.
    func revokeTrust(secretStore: any SecretStore) -> [GatewayTLSTrustFailure]
}

public struct LiveGatewayTLSProvisioner: GatewayTLSProvisioning {
    public init() {}

    public func identity(secretStore: any SecretStore) -> GatewayTLSIdentity? {
        try? identityStore(secretStore: secretStore).ensure()
    }

    public func installTrust(secretStore: any SecretStore) -> GatewayTLSTrustOutcome {
        let store = identityStore(secretStore: secretStore)
        let installer = LiveGatewayTLSTrustInstaller()
        guard let identity = try? store.ensure() else {
            return GatewayTLSTrustOutcome(
                isTrusted: false,
                failures: [.identityUnavailable]
            )
        }
        // Whatever a reissue replaced — this call's, or the listener's at
        // gateway start — goes first. An old anchor that refuses to leave is
        // clutter in the user's trust store, not a reason to withhold the
        // new one, so it stays on the ledger and the install proceeds.
        var failures = purgeSuperseded(store: store, installer: installer)
        do {
            try installer.installTrust(certificatePEM: identity.authorityPEM)
            let trusted = try installer.isTrusted(certificatePEM: identity.authorityPEM)
            if !trusted {
                failures.append(.anchorMissingAfterInstall)
            }
            return GatewayTLSTrustOutcome(isTrusted: trusted, failures: failures)
        } catch {
            failures.append(error)
            return GatewayTLSTrustOutcome(isTrusted: false, failures: failures)
        }
    }

    public func isTrusted(secretStore: any SecretStore) -> Bool {
        guard let anchorPEM = identityStore(secretStore: secretStore).installedAnchorPEM else {
            return false
        }
        return
            (try? LiveGatewayTLSTrustInstaller().isTrusted(certificatePEM: anchorPEM)) ?? false
    }

    public func revokeTrust(secretStore: any SecretStore) -> [GatewayTLSTrustFailure] {
        let store = identityStore(secretStore: secretStore)
        let installer = LiveGatewayTLSTrustInstaller()
        var failures = purgeSuperseded(store: store, installer: installer)
        guard let anchorPEM = store.installedAnchorPEM else {
            return failures
        }
        // The live anchor is not recorded as superseded even when its
        // removal fails: it is recoverable from `authority.pem`, and putting
        // it on the ledger would make the next install revoke the very
        // certificate it just put in.
        do {
            try installer.revokeTrust(certificatePEM: anchorPEM)
        } catch {
            failures.append(error)
        }
        return failures
    }

    /// Removes every anchor a reissue replaced and rewrites the ledger with
    /// whatever refused to go. Both connect and disconnect run it: each is a
    /// point where the machine should stop trusting a certificate we no
    /// longer serve.
    private func purgeSuperseded(
        store: GatewayTLSIdentityStore,
        installer: LiveGatewayTLSTrustInstaller
    ) -> [GatewayTLSTrustFailure] {
        var failures: [GatewayTLSTrustFailure] = []
        var stillSuperseded: [String] = []
        for superseded in store.supersededAnchorPEMs {
            do {
                try installer.revokeTrust(certificatePEM: superseded)
            } catch {
                failures.append(error)
                stillSuperseded.append(superseded)
            }
        }
        do {
            try store.retainSuperseded(stillSuperseded)
        } catch {
            failures.append(.supersededLedgerUnwritable(String(describing: error)))
        }
        return failures
    }

    private func identityStore(secretStore: any SecretStore) -> GatewayTLSIdentityStore {
        GatewayTLSIdentityStore(
            directory: GatewayTLSIdentityStore.liveDirectory(),
            secretStore: secretStore
        )
    }
}
