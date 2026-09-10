import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Brand assets repository policies")
struct BrandAssetPolicyTests {
    @Test("Pinned geometry, provenance, MIT notice, packaging and documentation retain every brand contract")
    func repositoryContracts() throws {
        let files = try RepositoryFixture.policyFiles(BrandAssetPolicy.rules)
        #expect(BrandAssetPolicy.rules.flatMap { $0.violations(in: files) }.isEmpty)
    }

    @Test("A changed source revision or missing license notice is detected")
    func provenanceAndLicense() throws {
        var files = try RepositoryFixture.policyFiles(BrandAssetPolicy.rules)
        let path = "Sources/LittleSwitchUI/Components/BrandIcons/OpenCodeIcon.swift"
        files[path] = files[path]?.replacingOccurrences(
            of: "4aaf4ee1fb2678a7f989ea570f0f6ce14a9abf75", with: "unreviewed-revision")
        files["THIRD_PARTY_NOTICES.md"] = ""
        let issues = BrandAssetPolicy.rules.flatMap { $0.violations(in: files) }
        #expect(issues.contains { $0.contains(path) && $0.contains("4aaf4ee1fb2678a7f989ea570f0f6ce14a9abf75") })
        #expect(issues.contains { $0.contains("Permission is hereby granted") })
    }

    @Test("Reintroducing the manual license tree fails the consolidated-notice policy")
    func manualLicenseTree() throws {
        let snapshot = try RepositoryPolicyFileSystem.read(root: RepositoryFixture.root())
        let issues = RepositoryPolicies.violations(
            files: snapshot.files, paths: snapshot.paths.union(["packaging/licenses"]), rootPath: "/fixture")
        #expect(issues.contains("packaging/licenses must be absent; bundle the consolidated THIRD_PARTY_NOTICES.md"))
    }

    @Test("Text policy failures identify missing files, required contracts and forbidden contracts")
    func readableFailures() {
        let rule = RepositoryTextRule("asset.swift", required: ["pinned provenance"], forbidden: ["unlicensed"])
        #expect(rule.violations(in: [:]) == ["Missing policy file: asset.swift"])
        #expect(
            rule.violations(in: ["asset.swift": "unlicensed"]) == [
                "asset.swift: required contract is missing: pinned provenance",
                "asset.swift: forbidden contract is present: unlicensed",
            ])
        #expect(rule.violations(in: ["asset.swift": "pinned provenance"]).isEmpty)
    }
}
