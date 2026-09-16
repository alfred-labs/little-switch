import Foundation
import Testing

@testable import RepositoryTooling

@Suite("User-visible string repository policy")
struct UserVisibleStringPolicyTests {
    @Test("The repository gate only reports untranslated UI Swift sources in deterministic order")
    func repositoryScope() {
        let files = [
            "Sources/LittleSwitchUI/ZCopy.swift": #"Button("Save") {}"#,
            "Sources/LittleSwitchUI/ACopy.swift": #"Text("Settings")"#,
            "Sources/LittleSwitchUI/Accepted.swift": #"""
            Text(L10n.resource("Localized"))
            Text(verbatim: "X-Api-Key")
            window.title = ProductIdentity.displayName
            """#,
            "Sources/LittleSwitchUI/Copy.txt": #"Text("Documentation")"#,
            "Sources/LittleSwitchCore/Copy.swift": #"Text("Outside UI")"#,
            "Sources/LittleSwitchUIOther/Copy.swift": #"Text("Outside target")"#,
            "Tests/LittleSwitchUITests/Copy.swift": #"Text("Test fixture")"#,
        ]
        let issues = RepositoryPolicies.violations(files: files, paths: [], rootPath: "/fixture")
        let findings = issues.filter { issue in files.keys.contains { issue.hasPrefix($0 + ":") } }
        #expect(
            findings == [
                #"Sources/LittleSwitchUI/ACopy.swift:1:6: Text: "Settings""#,
                #"Sources/LittleSwitchUI/ZCopy.swift:1:8: Button: "Save""#,
            ])
    }

    @Test("The actual UI contains no unlocalized display literals")
    func repositoryUI() throws {
        let directory = try RepositoryFixture.root().appendingPathComponent("Sources/LittleSwitchUI")
        #expect(try UserVisibleStringScanner.scan(directory: directory).isEmpty)
    }

    @Test("The repository command reports UI violations through its failing exit status")
    func repositoryCommand() throws {
        try withTemporaryDirectory { root in
            let directory = root.appendingPathComponent("Sources/LittleSwitchUI")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(#"Text("Settings")"#.utf8).write(to: directory.appendingPathComponent("Copy.swift"))

            let result = try ToolingCLI.run(["repo", "check", "--root", root.path], currentDirectory: root)
            #expect(result.status == 1)
            #expect(result.stdout.isEmpty)
            #expect(result.stderr.contains(#"Sources/LittleSwitchUI/Copy.swift:1:6: Text: "Settings""#))
        }
    }
}
