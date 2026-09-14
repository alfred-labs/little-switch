import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Magic string policy boundaries")
struct MagicStringQualificationTests {
    @Test func invalidCatalogueIsReportedWithoutSuppressingRawKeys() throws {
        let emptyBaseline = try #require(String(data: MagicStringBaseline(violations: []).encoded(), encoding: .utf8))
        let issues = MagicStringPolicy.check(files: [
            MagicStringPolicy.cataloguePath: #"{"formatVersion":2,"properties":[],"enums":[]}"#,
            MagicStringPolicy.baselinePath: emptyBaseline,
            "Sources/LittleSwitchCore/Protocols/Adapter.swift": #"let value = payload["type"]"#,
        ])
        #expect(
            issues == [
                "Invalid magic string catalogue: Unsupported magic string catalogue version 2",
                "Sources/LittleSwitchCore/Protocols/Adapter.swift:1:21: raw key \"type\" (subscript)",
            ])
    }

    @Test func missingUpdateInputsFailWithoutCreatingABaseline() throws {
        try withTemporaryDirectory { root in
            #expect(
                throws: RepositoryPolicyError(issues: [
                    "Missing magic string catalogue: \(MagicStringPolicy.cataloguePath)"
                ])
            ) {
                try MagicStringPolicy.updateBaseline(root: root, action: .initialize)
            }
            let catalogue = root.appendingPathComponent(MagicStringPolicy.cataloguePath)
            try FileManager.default.createDirectory(
                at: catalogue.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(#"{"formatVersion":1,"properties":[],"enums":[]}"#.utf8).write(to: catalogue)
            #expect(
                throws: RepositoryPolicyError(issues: [
                    "Missing magic string baseline: \(MagicStringPolicy.baselinePath)"
                ])
            ) {
                try MagicStringPolicy.updateBaseline(root: root, action: .prune)
            }
            #expect(
                !FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(MagicStringPolicy.baselinePath).path))
        }
    }

    @Test func catalogueKeepsStringEnumsAndRejectsCompositeEnumValues() throws {
        let prefix = #"{"formatVersion":1,"properties":[],"enums":[{"root":"Root","path":"/kind","values":"#
        let catalogue = try MagicStringCatalogue(data: Data((prefix + #"["known",null,true,false,1,1.5]}]}"#).utf8))
        #expect(catalogue.enums.map(\.values) == [["known"]])
        for value in ["[]", "{}"] {
            do {
                _ = try MagicStringCatalogue(data: Data((prefix + "[\(value)]}]}").utf8))
                Issue.record("Composite enum values must not become string catalogue evidence")
            } catch DecodingError.dataCorrupted(let context) {
                #expect(context.debugDescription == "Expected an enum scalar")
            }
        }
    }

    @Test func unknownOperatorsDoNotHideKeysAndOrdinalsStayPerIdentity() {
        let result = MagicKeyScanner.scan(
            source: #"func parse() { consume(payload["type"] <~> payload["type"], payload["role"], payload["type"]) }"#,
            filePath: "Adapter.swift")
        #expect(result.map(\.literal.value) == ["type", "type", "role", "type"])
        #expect(result.map(\.ordinal) == [1, 2, 1, 3])
        #expect(result.allSatisfy { $0.anchor == "func parse()" && $0.rule == .subscriptKey })
    }

    @Test func scopedFilesIncludeCommonAndStayInPathOrder() {
        let result = MagicStringPolicy.scan(
            files: [
                "Sources/LittleSwitchCommon/Domain/Usage/Usage.swift": #"consume(payload["shared"])"#,
                "Sources/LittleSwitchCore/Tools/B.swift": #"consume(payload["b"])"#,
                "Sources/LittleSwitchCore/Protocols/A.swift": #"consume(payload["a"])"#,
                "Sources/LittleSwitchCore/Gateway/C.swift": #"consume(payload["c"])"#,
                "Sources/LittleSwitchCore/Outside.swift": #"consume(payload["outside"])"#,
                "Sources/LittleSwitchCore/Protocols/README.md": #"consume(payload["documentation"])"#,
            ], catalogue: .empty)
        #expect(result.map(\.literal.value) == ["shared", "c", "a", "b"])
    }

    @Test func malformedGitHistoryOutputCannotDisableTheRatchet() throws {
        #expect(
            throws: RepositoryPolicyError(issues: ["Invalid magic string baseline Git history"])
        ) {
            try MagicStringBaselineStore.revisionIDs(in: Data([0xFF]))
        }
        #expect(try MagicStringBaselineStore.revisionIDs(in: Data()).isEmpty)
        let revision = String(repeating: "a", count: 40)
        #expect(try MagicStringBaselineStore.revisionIDs(in: Data((revision + "\n").utf8)) == [Substring(revision)])
    }
}

@Suite("Generic declaration anchor identity")
struct MagicStringAnchorQualificationTests {
    @Test(arguments: [
        (
            #"extension Adapter where T: Equatable { func parse<U>(_ value: U) async throws -> Int where U: Sendable { payload["type"] } }"#,
            "extension AdapterwhereT:Equatable/func parse<U>(_:U)asyncthrows->IntwhereU:Sendable"
        ),
        (
            #"struct Adapter { init?<T>(_ value: T) where T: Hashable { consume(payload["type"]) } }"#,
            "struct Adapter/init?<T>(_:T)whereT:Hashable"
        ),
        (
            #"struct Adapter { subscript(_ key: String) -> Int { payload["type"] } }"#,
            "struct Adapter/subscript(_:String)->Int"
        ),
    ])
    func signaturesRetainTheirConstraints(source: String, anchor: String) {
        let original = MagicKeyScanner.scan(source: source, filePath: "Adapter.swift")
        #expect(original.map(\.anchor) == [anchor])
        let moved = MagicKeyScanner.scan(
            source: source.replacingOccurrences(of: "Int", with: "Double").replacingOccurrences(
                of: "Hashable", with: "Equatable"),
            filePath: "Adapter.swift")
        #expect(MagicStringBaseline(violations: original).additionalViolations(in: moved) == moved)
    }
}
