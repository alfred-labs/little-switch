import Crypto
import Foundation
import NIOSSL
import SwiftASN1

/// Codex's HTTP client does not consistently use macOS user trust settings.
/// Its explicit CA bundle is additive to system roots. Preserve the effective
/// user bundle and add only the public authority of our HTTPS listener.
public struct ChatGPTLaunchTrust: Sendable {
    public enum Error: Swift.Error {
        case invalidCertificateBundle
    }

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func prepare(
        inheriting environment: [String: String],
        authorityPEM: String
    ) throws -> [String: String] {
        var result = try ChatGPTLaunchEnvironment.connected(inheriting: environment)
        // Match Codex's precedence; do not replace SSL_CERT_FILE or broaden
        // other applications' trust configuration.
        let inheritedPath =
            ["CODEX_CA_CERTIFICATE", "SSL_CERT_FILE"]
            .compactMap { environment[$0] }
            .first { !$0.isEmpty }
        var certificates: [NIOSSLCertificate] = []
        if let inheritedPath {
            certificates = try Self.certificates(in: Data(contentsOf: URL(fileURLWithPath: inheritedPath)))
        }
        certificates += try Self.certificates(in: Data(authorityPEM.utf8))
        var seen = Set<Data>()
        var pem = ""
        for certificate in certificates {
            let bytes = try certificate.toDERBytes()
            guard seen.insert(Data(bytes)).inserted else { continue }
            pem += PEMDocument(type: "CERTIFICATE", derBytes: bytes).pemString + "\n"
        }
        let data = Data(pem.utf8)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        // Immutable names keep a rollback's already-running process on its
        // original trust bundle when the user's certificates change.
        let file = directory.appending(path: "\(digest).pem")
        if (try? Data(contentsOf: file)) != data {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try AtomicFileWriter.write(data, to: file, backupDirectory: directory, backupLimit: 0)
        }
        result["CODEX_CA_CERTIFICATE"] = file.path
        return result
    }

    private static func certificates(in data: Data) throws -> [NIOSSLCertificate] {
        guard let pem = String(data: data, encoding: .utf8) else { throw Error.invalidCertificateBundle }
        // Match Codex's OpenSSL label normalization. NIOSSL validates each
        // certificate and emits only its DER, excluding X509_AUX metadata.
        // Its PEM reader also accepts line wrapping beyond SwiftASN1's
        // required 64 columns; use SwiftASN1 only for canonical output.
        let normalized =
            pem
            .replacingOccurrences(of: "BEGIN TRUSTED CERTIFICATE", with: "BEGIN CERTIFICATE")
            .replacingOccurrences(of: "END TRUSTED CERTIFICATE", with: "END CERTIFICATE")
        var certificates: [NIOSSLCertificate] = []
        var block: String?
        for rawLine in normalized.split(whereSeparator: \.isNewline) {
            // Codex accepts spaces after PEM markers. Normalize those too
            // so a root cannot silently disappear from a mixed bundle.
            let line = rawLine.dropLast(rawLine.reversed().prefix { $0 == " " }.count)
            if line == "-----BEGIN CERTIFICATE-----" {
                guard block == nil else { throw Error.invalidCertificateBundle }
                block = String(line) + "\n"
            } else if var current = block {
                current += line + "\n"
                if line == "-----END CERTIFICATE-----" {
                    certificates.append(try NIOSSLCertificate(bytes: Array(current.utf8), format: .pem))
                    block = nil
                } else {
                    block = current
                }
            }
        }
        guard block == nil, !certificates.isEmpty else { throw Error.invalidCertificateBundle }
        return certificates
    }
}
