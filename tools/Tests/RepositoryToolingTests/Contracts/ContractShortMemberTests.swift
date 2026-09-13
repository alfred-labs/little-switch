import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Short generated member names")
struct ContractShortMemberTests {
    @Test func shortMembersKeepRawValuesAndMeetTheRepositoryNamingRule() throws {
        #expect(ContractSwiftNames.member("a") == "valueA")
        #expect(ContractSwiftNames.member("1") == "value1")
        #expect(ContractSwiftNames.member("x") == "x")
        #expect(ContractSwiftNames.member("y") == "y")
        let graph = try graph(#"{"enum":["a","b","x","y"]}"#)
        let file = try #require(ContractSwiftEmitter.emit(graph: graph).first)
        #expect(file.source.contains("case valueA = \"a\""))
        try withTemporaryDirectory { root in
            let path = root.appendingPathComponent("ShortMembers.swift")
            try Data(ContractSwiftFormat.format(file.source).utf8).write(to: path)
            let repository = try RepositoryFixture.root()
            let lint = try RepositoryProcess.run(
                URL(fileURLWithPath: "/usr/bin/env"),
                arguments: [
                    "swiftlint", "lint", "--strict", "--quiet", "--no-cache", "--config",
                    repository.appendingPathComponent(".swiftlint.yml").path, path.path,
                ],
                directory: root)
            #expect(lint.status == 0, "\(lint.stdout)\(lint.stderr)")
        }
    }

    @Test func shortMemberNormalizationStillRejectsCollidingSourceValues() throws {
        #expect(throws: ContractGenerationError.self) {
            try ContractSwiftEmitter.emit(graph: graph(#"{"enum":["a","value_a"]}"#))
        }
    }

    private func graph(_ schema: String) throws -> ContractGraph {
        try ContractSchemaReader.read(data: Data(schema.utf8), rootID: "ShortMembers")
    }
}
