import ArgumentParser

struct RepositoryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "repo",
        abstract: "Validate repository policies.",
        subcommands: [
            CommitMessageCommand.self, RepositoryCheckCommand.self, MagicStringScanCommand.self,
            UserVisibleStringScanCommand.self,
        ]
    )

    @OptionGroup var options: RepositoryOptions
}
