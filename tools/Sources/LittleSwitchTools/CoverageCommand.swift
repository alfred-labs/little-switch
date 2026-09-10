import ArgumentParser
import Foundation
import RepositoryTooling

struct CoverageCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "coverage",
        abstract: "Classify production sources and enforce exact line coverage.",
        subcommands: [CoverageScopeCommand.self, CoverageVerifyCommand.self]
    )

    @OptionGroup var options: RepositoryOptions
}

struct CoverageScopeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scope", abstract: "Print sorted measured production source paths, one per line."
    )

    @OptionGroup var options: RepositoryOptions

    @Option(help: "Exclusion TSV path relative to the package root.", completion: .file())
    var manifest = "tools/ci/swift-coverage-exclusions.tsv"

    @Flag(help: "Print measured paths (also the default).")
    var measured = false

    func run() throws {
        let scope = try CoverageScope.load(root: options.resolve("."), manifestPath: manifest)
        for path in scope.measured { print(path) }
    }
}

struct CoverageVerifyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "verify", abstract: "Require exactly 100.00% lines per measured source and measured TOTAL."
    )

    @OptionGroup var options: RepositoryOptions

    @Option(help: "File with one measured source path per line.", completion: .file())
    var measuredList: String

    @Option(help: "Captured llvm-cov report, including stderr.", completion: .file())
    var report: String

    @Option(help: "Optional raw linked-source report checked for warnings and a unique TOTAL.", completion: .file())
    var rawReport: String?

    func run() throws {
        let contents = try String(contentsOf: options.resolve(measuredList), encoding: .utf8)
        var sources = contents.components(separatedBy: "\n")
        if sources.last?.isEmpty == true { sources.removeLast() }
        try CoverageReport.validate(
            measuredSources: sources,
            report: String(contentsOf: options.resolve(report), encoding: .utf8),
            rootPath: options.resolve(".").resolvingSymlinksInPath().path)
        if let rawReport {
            try CoverageReport.validateRaw(String(contentsOf: options.resolve(rawReport), encoding: .utf8))
        }
    }
}
