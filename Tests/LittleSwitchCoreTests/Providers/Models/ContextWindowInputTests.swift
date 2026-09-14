import Testing

@testable import LittleSwitchCore

@Suite("Context window input")
struct ContextWindowInputTests {
    @Test("Context input accepts integer, k, and m values")
    func parsesContextInput() throws {
        #expect(try ContextWindowInput.parse("") == nil)
        #expect(try ContextWindowInput.parse(" 262144 ") == 262_144)
        #expect(try ContextWindowInput.parse("400k") == 400_000)
        #expect(try ContextWindowInput.parse("1M") == 1_000_000)
        #expect(throws: ContextWindowInput.Error.invalid) {
            try ContextWindowInput.parse("unknown")
        }
        #expect(throws: ContextWindowInput.Error.invalid) {
            try ContextWindowInput.parse("0")
        }
        #expect(throws: ContextWindowInput.Error.invalid) {
            try ContextWindowInput.parse("\(Int.max)k")
        }
    }
}
