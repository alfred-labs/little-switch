import Testing

@testable import RepositoryTooling

@Suite("Magic string declaration anchors")
struct MagicStringAnchorTests {
    @Test("Type methods cannot transfer an allowance to instance methods", arguments: ["static", "class"])
    func distinguishesMethodKind(modifier: String) {
        let original = scan(
            "class Adapter { \(modifier) func parse() { consume(payload[\"type\"]) }; func parse() {} }")
        let moved = scan("class Adapter { \(modifier) func parse() {}; func parse() { consume(payload[\"type\"]) } }")

        #expect(original.map(\.anchor) == ["class Adapter/\(modifier) func parse()"])
        #expect(MagicStringBaseline(violations: original).additionalViolations(in: moved) == moved)
    }

    @Test("Type properties cannot transfer an allowance to instance properties", arguments: ["static", "class"])
    func distinguishesPropertyKind(modifier: String) {
        let original = scan(
            "class Adapter { \(modifier) var value: Any? { payload[\"type\"] }; var value: Any? { nil } }")
        let moved = scan("class Adapter { \(modifier) var value: Any? { nil }; var value: Any? { payload[\"type\"] } }")

        #expect(original.map(\.anchor) == ["class Adapter/\(modifier) binding value"])
        #expect(MagicStringBaseline(violations: original).additionalViolations(in: moved) == moved)
    }

    @Test("Constrained initializers keep distinct allowances")
    func distinguishesInitializerConstraints() {
        let original = scan("struct Adapter<T> { init() where T == Int { consume(payload[\"type\"]) } }")
        let moved = scan("struct Adapter<T> { init() where T == String { consume(payload[\"type\"]) } }")

        #expect(MagicStringBaseline(violations: original).additionalViolations(in: moved) == moved)
    }

    @Test("Generic subscript constraints keep distinct allowances")
    func distinguishesSubscriptConstraints() {
        let original = scan("struct Adapter { subscript<T>(key: T) -> Any? where T: Equatable { payload[\"type\"] } }")
        let moved = scan("struct Adapter { subscript<T>(key: T) -> Any? where T: Hashable { payload[\"type\"] } }")

        #expect(MagicStringBaseline(violations: original).additionalViolations(in: moved) == moved)
    }

    private func scan(_ source: String) -> [MagicKeyScanner.Violation] {
        MagicKeyScanner.scan(source: source, filePath: "Adapter.swift")
    }
}
