import Foundation
import Testing

@Suite("AppKit SwiftPM test runner")
struct AppKitSwiftTestRunnerTests {
    @Test("Application Swift Testing uses direct AppKit hosts so DYLD environment survives launch")
    func applicationSwiftTestingUsesDirectAppKitHosts() throws {
        let package = try RepositoryFixture.text("Package.swift")
        let mise = try RepositoryFixture.text(".mise.toml")
        let coverage = try RepositoryFixture.text("tools/ci/check-swift-coverage.sh")
        let standardToolsetData = Data(try RepositoryFixture.text("tools/ci/appkit-test-runner.json").utf8)
        let coverageToolsetData = Data(
            try RepositoryFixture.text("tools/ci/appkit-coverage-test-runner.json").utf8)
        let standardToolset = try JSONSerialization.jsonObject(with: standardToolsetData) as? [String: Any]
        let coverageToolset = try JSONSerialization.jsonObject(with: coverageToolsetData) as? [String: Any]

        #expect(
            package.contains(".executable(name: \"LittleSwitchUITestHost\", targets: [\"LittleSwitchUITestHost\"])")
                && package.contains("name: \"LittleSwitchUITestHost\""))
        #expect(mise.contains("--toolset tools/ci/appkit-test-runner.json"))
        #expect(coverage.contains("--disable-xctest"))
        #expect(
            coverage.contains(
                "--toolset tools/ci/appkit-coverage-test-runner.json"))
        #expect(mise.contains("--disable-xctest"))
        #expect(
            standardToolset?["testRunner"] as? [String: String] == [
                "path": "../../.build/out/Products/Debug/LittleSwitchUITestHost"
            ])
        #expect(
            coverageToolset?["testRunner"] as? [String: String] == [
                "path": "../../.build/coverage/out/Products/Debug/LittleSwitchUITestHost"
            ])
    }
}
