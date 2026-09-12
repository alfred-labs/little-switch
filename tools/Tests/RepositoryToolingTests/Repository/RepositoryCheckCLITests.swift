import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Repository policy command")
struct RepositoryCheckCLITests {
    @Test("Check validates the repository without changing files")
    func check() throws {
        let root = try RepositoryFixture.root()
        let result = try ToolingCLI.run(["repo", "check", "--root", root.path], currentDirectory: root)
        #expect(result == .init(status: 0, stdout: "", stderr: ""))
    }
}

@Test("The repository check reports magic keys from the protocol layer")
func checkReportsMagicKeys() throws {
    let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
    let root = temporary.appendingPathComponent("repo-check-magic-\(UUID().uuidString)")
    let protocols = root.appendingPathComponent("Sources/LittleSwitchCore/Protocols", isDirectory: true)
    try FileManager.default.createDirectory(at: protocols, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data(#"let value = headers["x-magic"]"#.utf8)
        .write(to: protocols.appendingPathComponent("Magic.swift"))

    do {
        try RepositoryPolicyFileSystem.check(root: root)
        Issue.record("A raw protocol key unexpectedly passed the repository check")
    } catch let error as RepositoryPolicyError {
        #expect(error.issues.contains { $0.contains(#"raw key "x-magic""#) })
    }
}
