import Foundation
import Security

/// Whether an application bundle carries a Developer ID Application
/// signature — the precondition for Sparkle's updates to survive Gatekeeper
/// on the replacing install. A leaf certificate summary is the same signal
/// `codesign -dv` prints; anything else (ad-hoc, unsigned, unreadable)
/// counts as unsigned.
enum DeveloperIDSignatureProbe {
    static func isDeveloperIDSigned(_ bundleURL: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard
            SecStaticCodeCreateWithPath(
                bundleURL as CFURL,
                SecCSFlags(),
                &staticCode
            ) == errSecSuccess,
            let code = staticCode
        else {
            return false
        }

        var signingInformation: CFDictionary?
        guard
            SecCodeCopySigningInformation(
                code,
                SecCSFlags(rawValue: kSecCSSigningInformation),
                &signingInformation
            ) == errSecSuccess,
            let information = signingInformation as? [String: Any],
            let certificates = information[kSecCodeInfoCertificates as String] as? [SecCertificate],
            let leaf = certificates.first
        else {
            return false
        }

        guard let summary = SecCertificateCopySubjectSummary(leaf) as String? else {
            return false
        }
        return summary.hasPrefix("Developer ID Application:")
    }
}
