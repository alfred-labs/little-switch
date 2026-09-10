import Foundation
import Testing

@Suite("Release version integration")
struct ReleaseVersionIntegrationTests {
    @Test("The shell wrapper uses Swift validation and forwards marketing-version arguments")
    func wrapper() throws {
        try withTemporaryDirectory { root in
            let fixture = try ReleaseFixture(root: root)
            let first = try fixture.run("bump-version.sh")
            #expect(first.status == 0, "\(first.stderr)")
            #expect(first.stdout == "LittleSwitch 1.2.3 (build 13)\n")
            let second = try fixture.run("bump-version.sh", ["1.3.0"])
            #expect(second.status == 0, "\(second.stderr)")
            #expect(second.stdout == "LittleSwitch 1.3.0 (build 14)\n")
            let before = try fixture.read("packaging/version.env")
            for arguments in [["1.2.9"], [""], ["1.4.0\nBUILD_NUMBER=999"], ["1.4.0", "extra"]] {
                #expect(try fixture.run("bump-version.sh", arguments).status != 0)
                #expect(try fixture.read("packaging/version.env") == before)
            }
        }
    }

    @Test("The checked-out build counter never decreases below committed release history")
    func historicalBuild() throws {
        let root = try RepositoryFixture.root()
        let history = try RepositoryProcess.run(
            URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["log", "--format=%H", "--", "packaging/version.env"],
            directory: root)
        try #require(history.status == 0, "\(history.stderr)")
        let current = try #require(buildNumber(in: RepositoryFixture.text("packaging/version.env")))
        var foundCounter = false
        for commit in history.stdout.split(separator: "\n") {
            let contents = try RepositoryProcess.run(
                URL(fileURLWithPath: "/usr/bin/git"),
                arguments: ["show", "\(commit):packaging/version.env"],
                directory: root)
            guard contents.status == 0, let historical = buildNumber(in: contents.stdout) else {
                continue
            }
            foundCounter = foundCounter || historical != "0"
            #expect(current.count > historical.count || current.count == historical.count && current >= historical)
        }
        #expect(foundCounter)
    }

    private func buildNumber(in source: String) -> String? {
        for line in source.components(separatedBy: "\n") where line.hasPrefix("BUILD_NUMBER=") {
            let value = line.dropFirst("BUILD_NUMBER=".count)
            guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }) else { continue }
            let normalized = value.drop { $0 == "0" }
            return normalized.isEmpty ? "0" : String(normalized)
        }
        return nil
    }
}
