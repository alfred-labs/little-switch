import Foundation
import Testing

@Suite("Repository policy command")
struct RepositoryCheckCLITests {
    @Test("Check validates the repository without changing files")
    func check() throws {
        let root = try RepositoryFixture.root()
        let result = try ToolingCLI.run(["repo", "check", "--root", root.path], currentDirectory: root)
        #expect(result == .init(status: 0, stdout: "", stderr: ""))
    }
}
