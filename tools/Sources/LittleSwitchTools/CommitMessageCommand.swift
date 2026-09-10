import ArgumentParser
import Foundation
import RepositoryTooling

struct CommitMessageCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "commit-message",
        abstract: "Validate a Git commit message using Conventional Commit rules."
    )

    @OptionGroup var options: RepositoryOptions

    @Argument(help: "Commit message file, absolute or relative to --root.", completion: .file())
    var path: String

    func run() throws {
        let messageURL = options.resolve(path)
        let message: Data
        do {
            message = try Data(contentsOf: messageURL)
        } catch {
            throw CommitMessageReadError(path: messageURL.path, reason: error.localizedDescription)
        }
        // Preserve the existing Node validator's replacement of malformed UTF-8.
        // swiftlint:disable:next optional_data_string_conversion
        let text = String(decoding: message, as: UTF8.self)
        _ = try ConventionalCommit.validate(text).get()
    }
}
