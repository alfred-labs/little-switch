import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Codex catalog process runner")
struct CodexProcessRunnerTests {
    @Test("Every output byte is collected for fast and pipe-sized writes", arguments: [0, 128, 1_048_576])
    func completeOutput(size: Int) throws {
        let path = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let expected = Data((0..<size).map { UInt8($0 % 251) })
        try expected.write(to: path)

        for _ in 0..<(size == 128 ? 100 : 1) {
            let data = try CodexProcessRunner().run(
                executablePath: "/bin/cat",
                arguments: [path.path],
                environment: [:],
                workingDirectory: nil
            )
            #expect(data == expected)
        }
    }

    @Test("Process output includes bytes written after the parent process exits")
    func waitsForOutputEOF() throws {
        let data = try CodexProcessRunner().run(
            executablePath: "/bin/sh",
            arguments: ["-c", "(/bin/sleep 0.1; /usr/bin/printf complete) & exit 0"],
            environment: [:],
            workingDirectory: nil,
            timeout: 2
        )

        #expect(data == Data("complete".utf8))
    }

    @Test("Output EOF does not bypass the process exit status")
    func waitsForExitAfterOutputEOF() {
        #expect(throws: CodexNativeCatalog.Error.nonZeroExit(17)) {
            try CodexProcessRunner().run(
                executablePath: "/bin/sh",
                arguments: ["-c", "exec 1>&-; /bin/sleep 0.1; exit 17"],
                environment: [:],
                workingDirectory: nil
            )
        }
    }

    @Test("An inherited stdout writer cannot extend the collection deadline")
    func outputEOFTimeout() {
        #expect(throws: CodexNativeCatalog.Error.timedOut) {
            try CodexProcessRunner().run(
                executablePath: "/bin/sh",
                arguments: ["-c", "(/bin/sleep 0.3) & exit 0"],
                environment: [:],
                workingDirectory: nil,
                timeout: 0.05
            )
        }
    }

    @Test("A process exit failure is surfaced as a typed error")
    func nonZeroProcessExitIsTyped() {
        #expect(throws: CodexNativeCatalog.Error.nonZeroExit(1)) {
            try CodexProcessRunner().run(
                executablePath: "/usr/bin/false",
                arguments: [],
                environment: [:],
                workingDirectory: nil
            )
        }
    }

    @Test("A probe timeout terminates the process and reports the typed error")
    func processTimeoutIsTyped() {
        #expect(throws: CodexNativeCatalog.Error.timedOut) {
            try CodexProcessRunner().run(
                executablePath: "/bin/sleep",
                arguments: ["1"],
                environment: [:],
                workingDirectory: nil,
                timeout: 0.05
            )
        }
    }

    @Test("Timeout cleanup kills a child that ignores SIGTERM")
    func timeoutKillsUnresponsiveChild() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        #expect(throws: CodexNativeCatalog.Error.timedOut) {
            try CodexProcessRunner().run(
                executablePath: "/bin/sh",
                arguments: [
                    "-c", "trap '' TERM; printf '%s' \"$$\" > \"$1\"; while :; do /bin/sleep 1; done",
                    "catalog-test", path.path,
                ],
                environment: [:],
                workingDirectory: nil,
                timeout: 0.1
            )
        }
        let pid = try #require(Int32(String(contentsOf: path, encoding: .utf8)))
        let stillRunning = kill(pid, 0) == 0
        if stillRunning { kill(pid, SIGKILL) }
        #expect(!stillRunning)
    }

    @Test("Launch errors surface without leaving a pending pipe read")
    func launchFailure() {
        #expect(throws: CocoaError.self) {
            try CodexProcessRunner().run(
                executablePath: "/nonexistent-little-switch-codex",
                arguments: [],
                environment: [:],
                workingDirectory: nil
            )
        }
    }

    @Test("The process receives its working directory and explicit environment")
    func workingDirectoryAndEnvironment() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("marker".utf8).write(to: directory.appending(path: "output"))
        let data = try CodexProcessRunner().run(
            executablePath: "/bin/sh",
            arguments: ["-c", "printf '%s\\n' \"$CATALOG_TEST_VALUE\"; /bin/cat output"],
            environment: ["CATALOG_TEST_VALUE": "fixture"],
            workingDirectory: directory.path
        )

        #expect(data == Data("fixture\nmarker".utf8))
    }
}
