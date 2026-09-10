import ArgumentParser
import Foundation
import RepositoryTooling

struct ReleaseHomebrewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "homebrew", abstract: "Verify an immutable DMG and update its Homebrew cask.")

    @OptionGroup var options: RepositoryOptions
    @Option var version: String
    @Option var dmg: String
    @Option var cask: String
    @Option var releaseMetadata: String?
    @Flag var check = false

    func run() throws {
        let artifact = try ReleaseArtifactFileSystem.digest(options.resolve(dmg), version: version)
        let destination = options.resolve(cask)
        let contents = try Data(contentsOf: destination)
        guard let source = String(data: contents, encoding: .utf8) else {
            throw ValidationError("Homebrew cask must be UTF-8")
        }
        let updated = try HomebrewCask.update(source, version: version, checksum: artifact.checksum)
        if check { return }
        guard let releaseMetadata else { throw ValidationError("--release-metadata is required to update the cask") }
        try PublishedRelease.verify(
            Data(contentsOf: options.resolve(releaseMetadata)),
            version: version,
            checksum: artifact.checksum,
            size: artifact.size)
        try AtomicFileWriter.prepare(contents: Data(updated.utf8), at: destination, expectedContents: contents).commit()
    }
}
