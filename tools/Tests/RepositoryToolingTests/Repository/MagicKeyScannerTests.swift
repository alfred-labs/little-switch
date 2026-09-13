import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Magic key scanner")
struct MagicKeyScannerTests {
    @Test("Declaration anchors distinguish owners and count identical occurrences")
    func anchorsOccurrences() {
        let result = MagicKeyScanner.scan(
            source: """
                struct Adapter {
                    func first() { consume(payload["type"], payload["type"]) }
                    func second() { consume(payload["type"]) }
                }
                """,
            filePath: "Example.swift"
        )
        #expect(
            result.map(\.anchor) == [
                "struct Adapter/func first()", "struct Adapter/func first()", "struct Adapter/func second()",
            ])
        #expect(result.map(\.ordinal) == [1, 2, 1])
    }

    @Test("Dictionary default values are not subscript keys")
    func ignoresDefaultArgument() {
        let result = MagicKeyScanner.scan(
            source: #"let role = payload[Field.role, default: "assistant"]"#,
            filePath: "Example.swift"
        )
        #expect(result.isEmpty)
    }

    @Test("Unrelated comparisons remain outside the discriminant context")
    func ignoresUnrelatedComparison() throws {
        let result = MagicKeyScanner.scan(
            source: #"let value = payload[Field.type] as? String == Item.message.rawValue && userInput == "ordinary""#,
            filePath: "Example.swift",
            catalogue: try Self.catalogue()
        )
        #expect(result.isEmpty)
    }

    @Test(
        "Each parenthesized or combined discriminant comparison is reported once",
        arguments: [
            #"let selected = (payload[Field.type] as? String == "message") && "assistant" == (payload[Field.role] as? String) && userInput == "message""#,
            #"let selected = payload[Field.type] as? String == "message" && payload[Field.role] as? String != "assistant" && userInput == "message""#,
        ]
    )
    func reportsComparisonsWithPrecedence(source: String) throws {
        let result = MagicKeyScanner.scan(
            source: source,
            filePath: "Example.swift",
            catalogue: try Self.catalogue()
        )
        #expect(result.map(\.literal.value) == ["message", "assistant"])
        #expect(result.map(\.rule) == [.discriminantValue, .discriminantValue])
    }

    @Test("Dictionary values and switch cases require a catalogued field context")
    func reportsContextualDiscriminants() throws {
        let result = MagicKeyScanner.scan(
            source: """
                let item = [Field.type: "message", Field.name: "message", Field.content: "assistant"]
                switch payload[Field.role] as? String {
                case "assistant", "user": break
                default: break
                }
                switch userInput {
                case "message": break
                default: break
                }
                """,
            filePath: "Example.swift",
            catalogue: try Self.catalogue()
        )
        #expect(result.map(\.literal.value) == ["message", "assistant", "user"])
    }

    @Test("Explicit open owners do not inherit the tagged type or tool name vocabulary")
    func preservesOpenOwnerContexts() throws {
        let result = MagicKeyScanner.scan(
            source: """
                let type = payload[ErrorObject.type] as? String == "message"
                let unknown = payload[ErrorObject.type] as? String == "custom_error"
                let tool = [NamedTool.name: "message", Tool.name: "message", Field.name: "message"]
                """,
            filePath: "Example.swift",
            catalogue: try Self.catalogue()
        )
        #expect(result.map(\.literal.value) == ["message"])
        #expect(result.map(\.position.line) == [3])
    }

    @Test("Unqualified names remain open even when the catalogue contains only a named tool")
    func keepsUnqualifiedNamesOpen() throws {
        let catalogue = try MagicStringCatalogue(
            data: Data(
                #"""
                {
                  "formatVersion":1,
                  "properties":[{"root":"Tools","definition":"NamedTool","path":"/NamedTool/name","key":"name"}],
                  "enums":[{"root":"Tools","definition":"NamedTool","path":"/NamedTool/name","values":["computer"]}]
                }
                """#.utf8))
        let result = MagicKeyScanner.scan(
            source: #"let tools = [Field.name: "computer", NamedTool.name: "computer"]"#,
            filePath: "Example.swift",
            catalogue: catalogue
        )
        #expect(result.map(\.literal.value) == ["computer"])
    }

    private static func catalogue() throws -> MagicStringCatalogue {
        try MagicStringCatalogue(
            data: Data(
                #"""
                {
                  "formatVersion": 1,
                  "properties": [
                    {"root":"Response","definition":"Message","path":"/Message/type","key":"type"},
                    {"root":"Response","definition":"Message","path":"/Message/role","key":"role"},
                    {"root":"Response","definition":"NamedTool","path":"/NamedTool/name","key":"name"},
                    {"root":"Response","definition":"Tool","path":"/Tool/name","key":"name"},
                    {"root":"Error","definition":"ErrorObject","path":"/ErrorObject/type","key":"type"}
                  ],
                  "enums": [
                    {"root":"Response","definition":"Message","path":"/Message/type","values":["message"]},
                    {"root":"Response","definition":"Message","path":"/Message/role","values":["assistant","user",null]},
                    {"root":"Response","definition":"NamedTool","path":"/NamedTool/name","values":["message"]}
                  ]
                }
                """#.utf8))
    }

    @Test("Discriminant diagnostics retain their structured value and correct position")
    func reportsTypedDiscriminant() throws {
        let result = MagicKeyScanner.scan(
            source: #"let value = [Field.role: "assistant"]"#,
            filePath: "Example.swift",
            catalogue: try Self.catalogue()
        )
        #expect(
            result == [
                .init(
                    file: "Example.swift",
                    position: .init(line: 1, column: 26),
                    rule: .discriminantValue,
                    literal: .init(kind: .string, value: "assistant"),
                    anchor: "binding value",
                    ordinal: 1
                )
            ])
        #expect(result.map(\.description) == ["Example.swift:1:26: raw discriminant \"assistant\" (discriminant)"])
    }

    @Test("Subscripts and dictionary literals report positioned raw keys")
    func reportsViolationsWithPositions() {
        let source = """
            let value = headers["x-api-key"]
            let map = ["type": 1, other: 2]
            """

        let violations = MagicKeyScanner.scan(source: source, filePath: "Protocols/Example.swift")

        #expect(violations.map(\.rule) == [.subscriptKey, .dictionaryKey])
        #expect(violations.map(\.literal.value) == ["x-api-key", "type"])
        #expect(
            violations.map(\.description) == [
                "Protocols/Example.swift:1:21: raw key \"x-api-key\" (subscript)",
                "Protocols/Example.swift:2:12: raw key \"type\" (dict-literal)",
            ])
    }

    @Test("Interpolated keys stay visible instead of crashing the scan")
    func recordsInterpolatedKeys() {
        let violations = MagicKeyScanner.scan(
            source: #"let value = headers["\(name)-key"]"#, filePath: "Example.swift")
        #expect(violations.map(\.literal) == [.init(kind: .interpolated, value: #""\(name)-key""#)])
    }

    @Test("Directory scan keeps every occurrence and sorts deterministically")
    func directoryScanSorts() throws {
        // The enumerator resolves the symlinked temporary root (/var →
        // /private/var), so the scan root must resolve before children are
        // appended or the relative prefix never strips.
        let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let root = temporary.appendingPathComponent("magic-key-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let first = root.appendingPathComponent("A.swift")
        let second = root.appendingPathComponent("sub/B.swift")
        try FileManager.default.createDirectory(
            at: second.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"let allowed = payload["kind"]"#.utf8).write(to: first)
        try Data(
            #"let blocked = payload["status"]"#.utf8
        ).write(to: second)
        try Data(#"let zoned = payload["zone"]"#.utf8).write(to: root.appendingPathComponent("C.swift"))

        let violations = try MagicKeyScanner.scan(directory: root)

        // C.swift sorts before sub/B.swift, and the comparator only runs with
        // more than one violation.
        #expect(
            violations.map(\.description) == [
                "A.swift:1:23: raw key \"kind\" (subscript)",
                "C.swift:1:21: raw key \"zone\" (subscript)",
                "sub/B.swift:1:23: raw key \"status\" (subscript)",
            ])
        #expect(try MagicKeyScanner.scan(directory: root.appendingPathComponent("missing")).isEmpty)
    }
}
