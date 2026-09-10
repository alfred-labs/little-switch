import CryptoKit
import Foundation

package enum ReleaseArtifactFileSystem {
    package static func digest(_ file: URL, version: String) throws -> (checksum: String, size: UInt64) {
        try HomebrewCask.validateArtifactName(file.lastPathComponent, version: version)
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        var size: UInt64 = 0
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hash.update(data: chunk)
            size += UInt64(chunk.count)
        }
        return (hash.finalize().map { String(format: "%02x", $0) }.joined(), size)
    }
}
