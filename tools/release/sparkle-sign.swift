import CryptoKit
import Foundation

// Computes the Sparkle `edSignature` value for an update file: a base64
// Ed25519 signature over the file's exact bytes, matching Sparkle's
// `sign_update` output. Usage:
//
//   swift sparkle-sign.swift <private-key-file> <file-to-sign>

func signError(_ message: String) -> Never {
    FileHandle.standardError.write(Data("sparkle-sign: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 2 else {
    signError("usage: sparkle-sign.swift <private-key-file> <file-to-sign>")
}

let keyURL = URL(fileURLWithPath: arguments.first!)
let fileURL = URL(fileURLWithPath: arguments.dropFirst().first!)

guard let keyData = try? Data(contentsOf: keyURL),
      let seedBase64 = String(data: keyData, encoding: .utf8)?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ),
      let seed = Data(base64Encoded: seedBase64),
      let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed)
else {
    signError("could not read an Ed25519 private key from \(keyURL.path)")
}

guard let fileData = try? Data(contentsOf: fileURL) else {
    signError("could not read \(fileURL.path)")
}

guard let signature = try? privateKey.signature(for: fileData) else {
    signError("signing failed")
}

print(signature.base64EncodedString())
