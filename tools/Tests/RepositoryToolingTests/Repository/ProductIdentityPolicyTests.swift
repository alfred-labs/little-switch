import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Product identity repository policies")
struct ProductIdentityPolicyTests {
    @Test("The package, bundle and entire repository use the current product identity")
    func repositoryIdentity() throws {
        let root = try RepositoryFixture.root()
        let snapshot = try RepositoryPolicyFileSystem.read(root: root)
        #expect(ProductIdentityPolicy.rules.flatMap { $0.violations(in: snapshot.files) }.isEmpty)
        #expect(ProductIdentityPolicy.bundleViolations(snapshot.files["packaging/Info.plist"]).isEmpty)
        #expect(ProductIdentityPolicy.legacyViolations(files: snapshot.files, rootPath: root.path).isEmpty)
    }

    @Test("Only the five migration owners may contain old spellings")
    func legacyAllowlist() {
        let old = [
            ["Model", "Switch", "er"], ["LittleSwitch", "er"], ["little_switch", "er"],
            ["littleswitch", "er"], ["little-switch", "er"],
        ].map { $0.joined() }
        var files = Dictionary(
            uniqueKeysWithValues: ProductIdentityPolicy.allowedLegacyPaths.map { ($0, old.joined(separator: " ")) })
        files["docs/current.md"] = old.joined(separator: " ")
        let issues = ProductIdentityPolicy.legacyViolations(files: files, rootPath: "/fixture")
        #expect(issues == old.map { "docs/current.md contains legacy product spelling \($0)" })
        #expect(ProductIdentityPolicy.allowedLegacyPaths.count == 5)
    }

    @Test("An absolute repository directory is scrubbed before checking its spelling")
    func absoluteRoot() {
        let oldPath = "/tmp/" + ["little-switch", "er"].joined()
        #expect(
            ProductIdentityPolicy.legacyViolations(files: ["source.swift": oldPath + "/Sources"], rootPath: oldPath)
                .isEmpty)
    }

    @Test(
        "Malformed and nondictionary plists cannot satisfy the bundle contract",
        arguments: [nil, "not a plist", "<plist><array/></plist>"])
    func invalidPlist(contents: String?) {
        #expect(
            ProductIdentityPolicy.bundleViolations(contents) == [
                "packaging/Info.plist must be a valid property-list dictionary"
            ])
    }

    @Test("Plist values are checked semantically, not by unrelated matching strings")
    func wrongBundleValues() throws {
        let properties = [
            "CFBundleName": "Wrong", "unrelated": "LittleSwitch com.alfredlabs.littleswitch AppIcon.icns",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: properties, format: .xml, options: 0)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(
            ProductIdentityPolicy.bundleViolations(text) == [
                "packaging/Info.plist: CFBundleExecutable must equal LittleSwitch",
                "packaging/Info.plist: CFBundleIconFile must equal AppIcon.icns",
                "packaging/Info.plist: CFBundleIdentifier must equal com.alfredlabs.littleswitch",
                "packaging/Info.plist: CFBundleName must equal LittleSwitch",
            ])
    }
}
