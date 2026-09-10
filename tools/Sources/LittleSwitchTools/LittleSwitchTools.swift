import ArgumentParser

@main
struct LittleSwitchTools: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "littleswitch-tools",
        abstract: "Repository tools for LittleSwitch.",
        subcommands: [
            RepositoryCommand.self, CoverageCommand.self, ReleaseCommand.self, DiagnosticsCommand.self,
            MonitoringCommand.self,
        ]
    )

    @OptionGroup var options: RepositoryOptions
}
