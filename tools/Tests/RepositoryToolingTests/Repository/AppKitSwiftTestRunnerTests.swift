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

    @Test("The AppKit test host stays inside the format and lint gates")
    func appKitTestHostStaysInsideStyleGates() throws {
        let mise = try RepositoryFixture.text(".mise.toml")
        let swiftLint = try RepositoryFixture.text(".swiftlint.yml")

        #expect(
            mise.contains(
                "swift format lint --strict --recursive Sources Tests Package.swift "
                    + "tools/LittleSwitchUITestHost tools/Sources tools/Tests tools/Package.swift"))
        #expect(includedSwiftLintPaths(swiftLint).contains("tools/LittleSwitchUITestHost"))
    }

    @Test("The AX focus limitation is pinned to the affected GitHub runner")
    func axFocusLimitationIsPinnedToAffectedRunner() throws {
        let workflow = try RepositoryFixture.text(".github/workflows/build.yml")
        let unavailable = try RepositoryFixture.text(
            "Tests/LittleSwitchUITests/TestSupport/ConditionallyUnavailable.swift")
        let applyButton = try RepositoryFixture.text(
            "Tests/LittleSwitchUITests/MenuBar/MenuApplyButtonTests.swift")
        let providerKeyboard = try RepositoryFixture.text(
            "Tests/LittleSwitchUITests/Settings/Search/WebSearchProviderKeyboardTests.swift")
        let expectedPredicate =
            "ProcessInfo.processInfo.environment[\"LITTLESWITCH_AX_FOCUS_RUNNER_LIMITATION\"] "
            + "== \"github-macos-27\""

        #expect(
            workflow.contains(
                "runs-on: xcode-27\n    env:\n      LITTLESWITCH_AX_FOCUS_RUNNER_LIMITATION: github-macos-27"))
        #expect(
            unavailable.contains(expectedPredicate))
        #expect(!unavailable.contains("environment[\"CI\"]"))
        #expect(applyButton.contains("ConditionallyUnavailable.skipWhenAxFocusUnavailable(skipReason)"))
        #expect(providerKeyboard.contains("ConditionallyUnavailable.skipWhenAxFocusUnavailable(skipReason)"))
    }

    private func includedSwiftLintPaths(_ configuration: String) -> Set<String> {
        var section: String?
        var paths = Set<String>()
        for line in configuration.split(separator: "\n") {
            if !line.hasPrefix(" ") {
                section = line.hasSuffix(":") ? String(line.dropLast()) : nil
            } else if section == "included", line.hasPrefix("  - ") {
                paths.insert(String(line.dropFirst(4)))
            }
        }
        return paths
    }
}
