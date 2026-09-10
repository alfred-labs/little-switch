import CryptoKit
import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Release artifact file digest")
struct ReleaseArtifactFileSystemTests {
    @Test("Streaming digests account for every chunk and return the complete byte length")
    func multiChunkDigest() throws {
        try withTemporaryDirectory { root in
            let file = root.appendingPathComponent("LittleSwitch-1.2.3-arm64.dmg")
            let contents = Data(repeating: 97, count: 2_097_159)
            try contents.write(to: file)
            let digest = try ReleaseArtifactFileSystem.digest(file, version: "1.2.3")
            #expect(digest.size == 2_097_159)
            #expect(digest.checksum == SHA256.hash(data: contents).map { String(format: "%02x", $0) }.joined())
            try Data("abc".utf8).write(to: file)
            let small = try ReleaseArtifactFileSystem.digest(file, version: "1.2.3")
            #expect(small.checksum == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
            #expect(small.size == 3)
            #expect(throws: ReleaseValidationError.self) {
                try ReleaseArtifactFileSystem.digest(file, version: "9.0.0")
            }
            #expect(throws: (any Error).self) {
                try ReleaseArtifactFileSystem.digest(
                    root.appendingPathComponent("missing/LittleSwitch-1.2.3-arm64.dmg"), version: "1.2.3")
            }
        }
    }
}
