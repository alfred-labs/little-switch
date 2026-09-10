import Foundation
import Testing

@testable import RepositoryTooling

@Suite("App icon repository policies")
struct AppIconPolicyTests {
    @Test("The approved monochrome SVG and bundle generation contracts are preserved")
    func repositoryIcon() throws {
        let files = try RepositoryFixture.policyFiles(AppIconPolicy.rules)
        #expect(AppIconPolicy.rules.flatMap { $0.violations(in: files) }.isEmpty)
        #expect(AppIconPolicy.sourceViolations(files["packaging/AppIcon.svg"]).isEmpty)
    }

    @Test("Missing, malformed and non-SVG documents are rejected", arguments: [nil, "<svg", "<plist/>"])
    func invalidXML(source: String?) {
        #expect(AppIconPolicy.sourceViolations(source) == ["packaging/AppIcon.svg must be valid SVG XML"])
    }

    @Test("Duplicate IDs cannot disguise a missing approved element")
    func wrongGeometry() {
        let source = #"<svg viewBox="0 0 32 32"><g id="background"/><g id="background"/></svg>"#
        #expect(
            AppIconPolicy.sourceViolations(source) == [
                "packaging/AppIcon.svg must have a 1024-pixel square viewBox",
                "packaging/AppIcon.svg must contain exactly one background element",
                "packaging/AppIcon.svg must contain exactly one left-module element",
                "packaging/AppIcon.svg must contain exactly one right-module element",
                "packaging/AppIcon.svg must contain exactly one left-indicator element",
                "packaging/AppIcon.svg must contain exactly one right-indicator element",
                "packaging/AppIcon.svg must contain exactly one up-arrow element",
                "packaging/AppIcon.svg must contain exactly one down-arrow element",
            ])
    }
}
