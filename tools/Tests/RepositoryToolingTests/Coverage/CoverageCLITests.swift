import Foundation
import Testing

@Suite("Coverage command")
struct CoverageCLITests {
    @Test("Scope prints only sorted measured paths including spaces", arguments: [false, true])
    func scope(measured: Bool) throws {
        try withTemporaryDirectory { root in
            try CoverageFixture.write(
                at: root,
                sources: ["Sources/App/Z.swift", "Sources/App/A name.swift"],
                exclusions: "Sources/App/Z.swift\tnative boundary\n")
            let arguments = ["--root", root.path, "coverage", "scope"] + (measured ? ["--measured"] : [])

            let result = try ToolingCLI.run(arguments, currentDirectory: root)

            #expect(result == .init(status: 0, stdout: "Sources/App/A name.swift\n", stderr: ""))
        }
    }

    @Test("Verify accepts exact measured coverage and a lower raw total")
    func verify() throws {
        try withTemporaryDirectory { root in
            try Data("Sources/App/A.swift\n".utf8).write(to: root.appendingPathComponent("measured.txt"))
            try Data(CoverageFixture.report().utf8).write(to: root.appendingPathComponent("report.txt"))
            try Data(CoverageFixture.report(total: "50.00%").utf8).write(to: root.appendingPathComponent("raw.txt"))

            let result = try ToolingCLI.run(
                [
                    "coverage", "verify", "--measured-list", "measured.txt", "--report", "report.txt", "--raw-report",
                    "raw.txt",
                ], currentDirectory: root)

            #expect(result == .init(status: 0, stdout: "", stderr: ""))
        }
    }

    @Test("A child root overrides the mise invocation root for the independent tooling package")
    func toolingRoot() throws {
        try withTemporaryDirectory { root in
            let package = root.appendingPathComponent("tools", isDirectory: true)
            try CoverageFixture.write(at: package, manifest: "ci/scope.tsv")
            let result = try ToolingCLI.run(
                [
                    "--root", root.path, "coverage", "scope", "--root", package.path, "--manifest", "ci/scope.tsv",
                ], currentDirectory: root)
            #expect(result == .init(status: 0, stdout: "Sources/App/A.swift\n", stderr: ""))
        }
    }

    @Test("A symlinked executable still classifies the invocation directory")
    func executableSymlink() throws {
        try withTemporaryDirectory { root in
            try CoverageFixture.write(at: root)
            let link = root.appendingPathComponent("linked tools")
            try FileManager.default.createSymbolicLink(
                at: link, withDestinationURL: RepositoryProcess.toolingExecutable())
            let result = try RepositoryProcess.run(link, arguments: ["coverage", "scope"], directory: root)
            #expect(result == .init(status: 0, stdout: "Sources/App/A.swift\n", stderr: ""))
        }
    }

    @Test("Unsupported arguments and invalid scope fail without polluting stdout", arguments: [false, true])
    func errors(unsupported: Bool) throws {
        try withTemporaryDirectory { root in
            try CoverageFixture.write(at: root, exclusions: "Sources/App/*.swift\tnative boundary\n")
            let arguments = ["coverage", "scope"] + (unsupported ? ["--unsupported"] : [])
            let result = try ToolingCLI.run(arguments, currentDirectory: root)
            #expect(result.status != 0)
            #expect(result.stdout.isEmpty)
            #expect(result.stderr.contains(unsupported ? "--unsupported" : "wildcard"))
        }
    }

    @Test(
        "Verify rejects missing inputs, blank measured paths and malformed reports",
        arguments: ["missing", "empty", "blank", "report"])
    func verifyErrors(failure: String) throws {
        try withTemporaryDirectory { root in
            if failure != "missing" {
                let sources =
                    failure == "empty" ? "" : (failure == "blank" ? "Sources/App/A.swift\n\n" : "Sources/App/A.swift\n")
                try Data(sources.utf8).write(to: root.appendingPathComponent("measured.txt"))
            }
            let report = failure == "report" ? CoverageFixture.report(total: "50.00%") : CoverageFixture.report()
            try Data(report.utf8).write(to: root.appendingPathComponent("report.txt"))
            let result = try ToolingCLI.run(
                [
                    "coverage", "verify", "--measured-list", "measured.txt", "--report", "report.txt",
                ], currentDirectory: root)
            #expect(result.status != 0)
            #expect(result.stdout.isEmpty)
            #expect(!result.stderr.isEmpty)
        }
    }
}
