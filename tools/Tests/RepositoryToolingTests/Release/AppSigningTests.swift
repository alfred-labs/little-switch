import Foundation
import Testing

@Suite("Application signing policy")
struct AppSigningTests {
    @Test("Identity parsing never evaluates other dotenv values")
    func dotenv() throws {
        try withTemporaryDirectory { root in
            let file = root.appendingPathComponent(".env")
            let content =
                "UNRELATED_SECRET=$(touch \"\(root.path)/must-not-exist\")\nAPPLE_SIGNING_IDENTITY=\"Developer ID Application: Example (TEAMID1234)\"\n"
            try Data(content.utf8).write(to: file)
            let result = try resolver([file.path], directory: root)
            #expect(result.status == 0, "\(result.stderr)")
            #expect(result.stdout == "Developer ID Application: Example (TEAMID1234)\n")
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("must-not-exist").path))
        }
    }

    @Test("The application-specific identity overrides the shared Apple identity")
    func override() throws {
        try withTemporaryDirectory { root in
            let result = try resolver(
                ["/missing/.env"],
                directory: root,
                overrides: [
                    "APPLE_SIGNING_IDENTITY": "Developer ID Application: Apple",
                    "LITTLE_SWITCH_SIGN_IDENTITY": "Developer ID Application: LittleSwitch",
                ])
            #expect(result.status == 0)
            #expect(result.stdout == "Developer ID Application: LittleSwitch\n")
        }
    }

    @Test("Store builds declare only sandbox and client/server network entitlements")
    func entitlements() throws {
        let data = try Data(
            contentsOf: RepositoryFixture.root().appendingPathComponent("packaging/LittleSwitch.AppStore.entitlements"))
        let values = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Bool])
        #expect(
            values == [
                "com.apple.security.app-sandbox": true, "com.apple.security.network.client": true,
                "com.apple.security.network.server": true,
            ])
    }

    @Test("Developer ID builds resolve identity without sourcing dotenv or using Store entitlements")
    func developerIDBuild() throws {
        let script = try RepositoryFixture.text("tools/build-app.sh")
        for value in ["resolve-signing-identity.sh", ".signing.env", ".env"] { #expect(script.contains(value)) }
        #expect(script.range(of: #"(?:^|\n)\s*(?:\.|source)\s+[^\n]*\.env"#, options: .regularExpression) == nil)
        #expect(!script.contains("LittleSwitch.AppStore.entitlements"))
        #expect(!script.contains("--entitlements"))
        let data = try Data(contentsOf: RepositoryFixture.root().appendingPathComponent("packaging/Info.plist"))
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(
            plist["NSLocalNetworkUsageDescription"] as? String
                == "LittleSwitch accepts model requests from devices on your local network.")
    }

    private func resolver(
        _ arguments: [String],
        directory: URL,
        overrides: [String: String] = [:]
    ) throws -> RepositoryProcess.Result {
        try RepositoryProcess.run(
            RepositoryFixture.root().appendingPathComponent("tools/resolve-signing-identity.sh"),
            arguments: arguments,
            directory: directory,
            environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"].merging(overrides) { _, new in new })
    }
}
