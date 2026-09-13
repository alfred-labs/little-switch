import CryptoKit
import Foundation

struct ContractGenerationManifest: Codable, Equatable {
    struct File: Codable, Equatable {
        let path: String
        // Retained by Codable in the published ownership/provenance manifest.
        // periphery:ignore
        let sha256: String
    }

    let formatVersion: Int
    // Retained by Codable; check compares the full encoded manifest byte for byte.
    // periphery:ignore
    let generator: String
    // periphery:ignore
    let inputs: [File]
    let files: [File]

    func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data([10])
    }

    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

struct ContractUpstreamManifest: Decodable {
    struct Artifact: Decodable {
        let path: String
        let sha256: String
    }
    struct Source: Decodable {
        let id: String
        let package: String
        let version: String
    }
    let artifacts: [Artifact]
    let sources: [Source]?
}

struct ContractRootsManifest: Decodable {
    struct Root: Decodable {
        let name: String
        let schema: String
        let sdk: String?
    }
    let roots: [Root]
}
