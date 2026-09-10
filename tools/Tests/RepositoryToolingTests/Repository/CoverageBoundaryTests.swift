import Testing

@testable import RepositoryTooling

@Suite("Coverage boundaries repository policies")
struct CoverageBoundaryTests {
    @Test("All deterministic units remain in focused files and native handoff ownership stays in the system adapter")
    func boundaries() throws {
        let rules = CoverageBoundaryPolicy.rules
        let files = try RepositoryFixture.policyFiles(rules)
        #expect(rules.count == 38)
        #expect(rules.flatMap { $0.violations(in: files) }.isEmpty)
    }

    @Test("Moving native application discovery back into the deterministic handoff policy is rejected")
    func nativeLeak() throws {
        var files = try RepositoryFixture.policyFiles(CoverageBoundaryPolicy.rules)
        let policy = "Sources/LittleSwitchUI/Platform/ProcessHandoff/ApplicationHandoff.swift"
        files[policy, default: ""] += "\nlet application: NSRunningApplication\n"
        let issues = CoverageBoundaryPolicy.rules.flatMap { $0.violations(in: files) }
        #expect(
            issues.contains { $0.contains(policy) && $0.contains("forbidden") && $0.contains("NSRunningApplication") })
    }
}
