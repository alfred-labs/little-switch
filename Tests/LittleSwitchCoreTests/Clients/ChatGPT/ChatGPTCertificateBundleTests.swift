import Foundation
import NIOSSL
import SwiftASN1
import Testing

@testable import LittleSwitchCore

struct ChatGPTCertificateBundleTests {
    @Test("Codex's existing roots and TLS settings survive adding the loopback authority")
    func preservesInheritedCertificates() throws {
        let fixture = try ChatGPTCertificateFixture()
        let custom = try fixture.write(fixture.custom.authorityPEM + "\n" + fixture.custom.keyPEM, name: "custom.pem")
        let original = [
            "CODEX_CA_CERTIFICATE": custom.path,
            "SSL_CERT_FILE": "/unused/fallback.pem",
            "NODE_EXTRA_CA_CERTS": "/unchanged/node.pem",
            "PATH": "/usr/bin",
        ]
        let before = try Data(contentsOf: custom)
        let environment = try fixture.trust.prepare(inheriting: original, authorityPEM: fixture.authority)
        let bundle = try fixture.bundle(environment)
        #expect(try fixture.certificates(bundle) == fixture.expectedCertificates)
        #expect(environment["SSL_CERT_FILE"] == "/unused/fallback.pem")
        #expect(environment["NODE_EXTRA_CA_CERTS"] == "/unchanged/node.pem")
        #expect(environment["PATH"] == "/usr/bin")
        #expect(environment["NODE_TLS_REJECT_UNAUTHORIZED"] == nil)
        #expect(try Data(contentsOf: custom) == before)
        #expect(try !String(contentsOf: bundle, encoding: .utf8).contains("PRIVATE KEY"))
    }

    @Test("Empty Codex overrides use SSL_CERT_FILE without changing its value")
    func fallbackPrecedence() throws {
        let fixture = try ChatGPTCertificateFixture()
        let custom = try fixture.write(fixture.custom.authorityPEM, name: "fallback.pem")
        let original = ["CODEX_CA_CERTIFICATE": "", "SSL_CERT_FILE": custom.path]
        let environment = try fixture.trust.prepare(inheriting: original, authorityPEM: fixture.authority)
        #expect(try fixture.certificates(fixture.bundle(environment)) == fixture.expectedCertificates)
        #expect(environment["SSL_CERT_FILE"] == custom.path)
    }

    @Test("Certificate paths preserve spaces exactly as Codex does")
    func preservesPathBytes() throws {
        let fixture = try ChatGPTCertificateFixture()
        let custom = try fixture.write(fixture.custom.authorityPEM, name: "company CA.pem ")
        let environment = try fixture.trust.prepare(
            inheriting: ["CODEX_CA_CERTIFICATE": custom.path], authorityPEM: fixture.authority)
        #expect(try fixture.certificates(fixture.bundle(environment)) == fixture.expectedCertificates)
    }

    @Test("Repeated connection is idempotent and certificate changes do not overwrite an older launch")
    func stableBundleLifetime() throws {
        let fixture = try ChatGPTCertificateFixture()
        let first = try fixture.trust.prepare(inheriting: [:], authorityPEM: fixture.authority)
        let originalBundle = try fixture.bundle(first)
        let originalData = try Data(contentsOf: originalBundle)
        let repeated = try fixture.trust.prepare(inheriting: first, authorityPEM: fixture.authority)
        #expect(repeated == first)
        let changed = try fixture.trust.prepare(inheriting: first, authorityPEM: fixture.custom.authorityPEM)
        #expect(changed["CODEX_CA_CERTIFICATE"] != first["CODEX_CA_CERTIFICATE"])
        #expect(try Data(contentsOf: originalBundle) == originalData)
        #expect(try fixture.certificates(originalBundle).count == 1)
        #expect(try fixture.certificates(fixture.bundle(changed)).count == 2)
        try Data("corrupted".utf8).write(to: originalBundle)
        #expect(try fixture.trust.prepare(inheriting: [:], authorityPEM: fixture.authority) == first)
        #expect(try Data(contentsOf: originalBundle) == originalData)
    }

    @Test("An invalid explicit bundle cannot silently fall back to another root set", arguments: ["", "not PEM"])
    func rejectsInvalidBundle(pem: String) throws {
        let fixture = try ChatGPTCertificateFixture()
        let invalid = try fixture.write(pem, name: "invalid.pem")
        let fallback = try fixture.write(fixture.custom.authorityPEM, name: "fallback.pem")
        #expect(throws: (any Error).self) {
            try fixture.trust.prepare(
                inheriting: ["CODEX_CA_CERTIFICATE": invalid.path, "SSL_CERT_FILE": fallback.path],
                authorityPEM: fixture.authority)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.bundleDirectory.path))
    }

    @Test("Invalid listener certificates and unwritable destinations fail before producing a launch")
    func preparationFailures() throws {
        let fixture = try ChatGPTCertificateFixture()
        #expect(throws: (any Error).self) {
            try fixture.trust.prepare(inheriting: [:], authorityPEM: "invalid")
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.bundleDirectory.path))
        let file = try fixture.write("not a directory", name: "occupied")
        #expect(throws: (any Error).self) {
            try ChatGPTLaunchTrust(directory: file).prepare(inheriting: [:], authorityPEM: fixture.authority)
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == "not a directory")
    }

    @Test("Unrecognized PEM blocks cannot introduce additional trusted roots")
    func rejectsUnknownCertificateBlock() throws {
        let fixture = try ChatGPTCertificateFixture()
        let otherType = fixture.custom.authorityPEM.replacingOccurrences(of: "CERTIFICATE", with: "UNKNOWN CERTIFICATE")
        let source = try fixture.write(otherType, name: "nonstandard.pem")
        #expect(throws: (any Error).self) {
            try fixture.trust.prepare(
                inheriting: ["CODEX_CA_CERTIFICATE": source.path], authorityPEM: fixture.authority)
        }
    }

    @Test("Codex accepts OpenSSL trusted certificates with or without auxiliary data", arguments: [false, true])
    func preservesTrustedCertificates(auxiliaryData: Bool) throws {
        let fixture = try ChatGPTCertificateFixture()
        let certificate = try NIOSSLCertificate(bytes: Array(fixture.custom.authorityPEM.utf8), format: .pem)
        let bytes = try certificate.toDERBytes() + (auxiliaryData ? [0x30, 0x00] : [])
        let trustedPEM = PEMDocument(type: "TRUSTED CERTIFICATE", derBytes: bytes).pemString
        let source = try fixture.write(trustedPEM, name: "trusted.pem")
        let environment = try fixture.trust.prepare(
            inheriting: ["CODEX_CA_CERTIFICATE": source.path], authorityPEM: fixture.authority)
        let bundle = try fixture.bundle(environment)
        #expect(try fixture.certificates(bundle) == fixture.expectedCertificates)
        #expect(try !String(contentsOf: bundle, encoding: .utf8).contains("TRUSTED CERTIFICATE"))
    }

    @Test("Spaces after PEM markers cannot drop a root from a mixed bundle", arguments: [false, true])
    func preservesRootsWithSpacedMarkers(mixed: Bool) throws {
        let fixture = try ChatGPTCertificateFixture()
        let prefix = mixed ? try GatewayTLSIdentityFactory.make().authorityPEM : ""
        let spacedPEM = fixture.custom.authorityPEM
            .replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "-----BEGIN CERTIFICATE-----  ")
            .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "-----END CERTIFICATE-----  ")
        let source = try fixture.write(prefix + "\n" + spacedPEM, name: "spaced.pem")
        let environment = try fixture.trust.prepare(
            inheriting: ["CODEX_CA_CERTIFICATE": source.path], authorityPEM: fixture.authority)
        let expected = try NIOSSLCertificate.fromPEMBytes(
            Array((prefix + "\n" + fixture.custom.authorityPEM + "\n" + fixture.authority).utf8))
        #expect(try fixture.certificates(fixture.bundle(environment)) == expected)
    }

    @Test("Unreadable text and malformed certificate data cannot become trusted roots")
    func rejectsMalformedEncoding() throws {
        let fixture = try ChatGPTCertificateFixture()
        let source = fixture.directory.appending(path: "invalid-bytes.pem")
        try Data([0xFF]).write(to: source)
        #expect(throws: (any Error).self) {
            try fixture.trust.prepare(
                inheriting: ["CODEX_CA_CERTIFICATE": source.path], authorityPEM: fixture.authority)
        }
        try Data("-----BEGIN CERTIFICATE-----\nbm90IGEgcHVibGljIGNlcnRpZmljYXRl\n-----END CERTIFICATE-----\n".utf8)
            .write(to: source)
        #expect(throws: (any Error).self) {
            try fixture.trust.prepare(
                inheriting: ["CODEX_CA_CERTIFICATE": source.path], authorityPEM: fixture.authority)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.bundleDirectory.path))
    }

    @Test("Inherited certificates accept the line wrapping supported by Codex", arguments: [76, 4_096])
    func acceptsOtherPEMWrapping(width: Int) throws {
        let fixture = try ChatGPTCertificateFixture()
        let encoded = fixture.custom.authorityPEM.split(separator: "\n").dropFirst().dropLast().joined()
        let bytes = Array(encoded.utf8)
        let rows = try stride(from: 0, to: bytes.count, by: width).map { offset in
            try #require(String(bytes: bytes[offset..<min(offset + width, bytes.count)], encoding: .utf8))
        }
        let pem = (["-----BEGIN CERTIFICATE-----"] + rows + ["-----END CERTIFICATE-----"]).joined(separator: "\r\n")
        let source = try fixture.write(pem, name: "rewrapped.pem")
        let environment = try fixture.trust.prepare(
            inheriting: ["CODEX_CA_CERTIFICATE": source.path], authorityPEM: fixture.authority)
        #expect(try fixture.certificates(fixture.bundle(environment)) == fixture.expectedCertificates)
    }

    @Test("Incomplete or nested certificate blocks cannot be silently skipped", arguments: [false, true])
    func rejectsTruncatedBlock(nested: Bool) throws {
        let fixture = try ChatGPTCertificateFixture()
        let unfinished = fixture.authority + "\n-----BEGIN CERTIFICATE-----\n"
        let pem = unfinished + (nested ? fixture.custom.authorityPEM : "")
        let source = try fixture.write(pem, name: "incomplete.pem")
        #expect(throws: (any Error).self) {
            try fixture.trust.prepare(
                inheriting: ["CODEX_CA_CERTIFICATE": source.path], authorityPEM: fixture.authority)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.bundleDirectory.path))
    }
}

private final class ChatGPTCertificateFixture {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let authority: String
    let custom: GatewayTLSIdentityFactory.Issued
    var bundleDirectory: URL { directory.appending(path: "bundles") }
    var trust: ChatGPTLaunchTrust { ChatGPTLaunchTrust(directory: bundleDirectory) }
    var expectedCertificates: [NIOSSLCertificate] {
        get throws { try NIOSSLCertificate.fromPEMBytes(Array((custom.authorityPEM + "\n" + authority).utf8)) }
    }
    init() throws {
        authority = try GatewayTLSIdentityFactory.make().authorityPEM
        custom = try GatewayTLSIdentityFactory.make()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
    func write(_ pem: String, name: String) throws -> URL {
        let file = directory.appending(path: name)
        try Data(pem.utf8).write(to: file)
        return file
    }
    func bundle(_ environment: [String: String]) throws -> URL {
        URL(fileURLWithPath: try #require(environment["CODEX_CA_CERTIFICATE"]))
    }
    func certificates(_ file: URL) throws -> [NIOSSLCertificate] {
        try NIOSSLCertificate.fromPEMFile(file.path)
    }
}
