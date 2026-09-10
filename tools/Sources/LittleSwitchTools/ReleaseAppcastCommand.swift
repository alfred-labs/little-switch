import ArgumentParser
import Foundation
import RepositoryTooling

struct ReleaseAppcastCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "appcast", abstract: "Render a Sparkle appcast and retain release history.")

    @OptionGroup var options: RepositoryOptions
    @Option var version: String
    @Option var build: String
    @Option var dmg: String
    @Option var signature: String
    @Option var description = ""
    @Option var notesFile: String?
    @Option var replaceVersion: String?
    @Option var date: String?
    @Option var appcast: String?
    @Option var output = "-"

    func validate() throws {
        guard notesFile == nil || description.isEmpty else {
            throw ValidationError("--description and --notes-file are mutually exclusive")
        }
        guard !version.isEmpty, !build.isEmpty, !dmg.isEmpty, !signature.isEmpty else {
            throw ValidationError("--version, --build, --dmg and --signature must not be empty")
        }
    }

    func run() throws {
        let destination = output == "-" ? nil : options.resolve(output)
        let expected = try destination.flatMap { file in
            FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : nil
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: options.resolve(dmg).path)
        guard attributes[.type] as? FileAttributeType == .typeRegular, let length = attributes[.size] as? NSNumber
        else {
            throw ValidationError("DMG must be a regular file")
        }
        let previous = try appcast.map { try String(contentsOf: options.resolve($0), encoding: .utf8) } ?? ""
        let notes =
            try notesFile.map { AppcastHTML.markdown(try String(contentsOf: options.resolve($0), encoding: .utf8)) }
            ?? description
        let document = SparkleAppcast.render(
            .init(version: version, build: build, length: length.uint64Value, signature: signature),
            publicationDate: date ?? SparkleAppcast.publicationDate(Date()),
            description: notes,
            previous: previous,
            replacing: replaceVersion)
        if let destination {
            try AtomicFileWriter.prepare(contents: Data(document.utf8), at: destination, expectedContents: expected)
                .commit()
        } else {
            FileHandle.standardOutput.write(Data(document.utf8))
        }
    }
}
