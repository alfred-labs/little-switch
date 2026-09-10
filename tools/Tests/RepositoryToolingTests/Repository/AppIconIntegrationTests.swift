import Foundation
import Testing

@Suite("App icon Apple tools integration", .serialized)
struct AppIconIntegrationTests {
    @Test("Quick Look, sips and iconutil produce all ten required ICNS representations")
    func generatedIcon() throws {
        try withTemporaryDirectory { directory in
            let root = try RepositoryFixture.root()
            let icon = directory.appendingPathComponent("App Icon.icns")
            let generated = try RepositoryProcess.run(
                root.appendingPathComponent("tools/generate-app-icon.sh"),
                arguments: [icon.path],
                directory: root)
            try #require(generated.status == 0, "\(generated.stdout)\n\(generated.stderr)")
            let data = try Data(contentsOf: icon)
            #expect(data.count > 8)
            #expect(data.prefix(4) == Data("icns".utf8))
            let verified = try RepositoryProcess.run(
                root.appendingPathComponent("tools/ci/verify-app-icon.sh"),
                arguments: [icon.path],
                directory: root)
            #expect(verified.status == 0, "\(verified.stdout)\n\(verified.stderr)")
            #expect(verified.stdout == "Verified \(icon.path)\n")
        }
    }
}
