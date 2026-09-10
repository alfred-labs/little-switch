import CryptoKit
import Foundation

// Generates the EdDSA (Ed25519) key pair used to sign Sparkle appcast
// updates. Sparkle's `edSignature` is a plain Ed25519 signature over the
// update file bytes, so CryptoKit's Curve25519.Signing produces the same
// value Sparkle's own `sign_update` tool would.
//
// The private key is stored as base64 of the 32-byte seed so it can be
// re-imported anywhere without keychain tooling. Keep it out of every
// repository.

func keygenError(_ message: String) -> Never {
    FileHandle.standardError.write(Data("sparkle-keygen: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments
let force = arguments.contains("--force")
// The `swift` driver absolutizes file-looking arguments, so relative output
// paths cannot be honored reliably. The key location is fixed policy.
let resolvedPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/little-switch", isDirectory: true)
    .appendingPathComponent("sparkle-ed25519-private.key")

let fileManager = FileManager.default
if (try? fileManager.attributesOfItem(atPath: resolvedPath.path)) != nil, !force {
    keygenError("\(resolvedPath.path) already exists; pass --force to replace it")
}

let privateKey = Curve25519.Signing.PrivateKey()
let seedBase64 = privateKey.rawRepresentation.base64EncodedString()
let publicKeyBase64 = privateKey.publicKey.rawRepresentation.base64EncodedString()

try fileManager.createDirectory(
    at: resolvedPath.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try Data(seedBase64.utf8).write(to: resolvedPath, options: .atomic)
try fileManager.setAttributes(
    [.posixPermissions: 0o600],
    ofItemAtPath: resolvedPath.path
)

print("Private key written to \(resolvedPath.path) (keep it outside any repository)")
print("SUPublicEDKey: \(publicKeyBase64)")
