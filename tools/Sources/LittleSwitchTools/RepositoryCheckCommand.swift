import ArgumentParser
import RepositoryTooling

struct RepositoryCheckCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Check product identity, brand resources, UI localization and deterministic coverage boundaries."
    )

    @OptionGroup var options: RepositoryOptions

    func run() throws {
        try RepositoryPolicyFileSystem.check(root: options.resolve("."))
    }
}
