import ArgumentParser
import Foundation
import RepositoryTooling

struct ReleaseBumpCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bump", abstract: "Advance the monotonic build counter.")

    @OptionGroup var options: RepositoryOptions
    @Argument(help: "Optional new marketing version, with three numeric components.") var marketingVersion: String?
    @Option(help: "Version metadata file, relative to the repository root.") var file = "packaging/version.env"

    func run() throws {
        let destination = options.resolve(file)
        let contents = try Data(contentsOf: destination)
        guard let source = String(data: contents, encoding: .utf8) else {
            throw ValidationError("Version metadata must be UTF-8")
        }
        let update = try ReleaseVersion.bump(source, marketing: marketingVersion)
        try AtomicFileWriter.prepare(contents: Data(update.contents.utf8), at: destination, expectedContents: contents)
            .commit()
        print("LittleSwitch \(update.marketing) (build \(update.build))")
    }
}
