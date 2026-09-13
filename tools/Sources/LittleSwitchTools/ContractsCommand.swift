import ArgumentParser
import Foundation
import RepositoryTooling

struct ContractsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "contracts",
        abstract: "Generate and verify Swift wire contracts from pinned SDK snapshots.",
        subcommands: [ContractsGenerateCommand.self, ContractsCheckCommand.self])

    @OptionGroup var options: RepositoryOptions
}

struct ContractsGenerateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate", abstract: "Regenerate owned Swift contracts.")
    @OptionGroup var options: RepositoryOptions

    func run() throws {
        let files = try ContractGenerationFileSystem.generate(root: options.resolve("."))
        print("Generated \(files.count) Swift files.")
    }
}

struct ContractsCheckCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check", abstract: "Compare generated contracts without changing the checkout.")
    @OptionGroup var options: RepositoryOptions

    func run() throws {
        let files = try ContractGenerationFileSystem.check(root: options.resolve("."))
        print("Verified \(files.count) Swift files.")
    }
}
