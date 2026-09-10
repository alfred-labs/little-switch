import ArgumentParser

struct ReleaseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "release",
        abstract: "Validate and prepare LittleSwitch release artifacts.",
        subcommands: [ReleaseBumpCommand.self, ReleaseAppcastCommand.self, ReleaseHomebrewCommand.self]
    )

    @OptionGroup var options: RepositoryOptions
}
