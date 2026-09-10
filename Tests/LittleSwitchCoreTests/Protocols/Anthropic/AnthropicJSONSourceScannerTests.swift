import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Anthropic JSON source scanner")
struct AnthropicJSONSourceScannerTests {
    @Test("The scanner traverses every JSON family and locates only nested input tokens")
    func completeJSONFamilies() {
        let text = #"{"message":{"usage":{"input_tokens":1e+2}},"array":[true,false,null,"a\\\"b",-2.5E-1,{}]}"#
        let bytes = Array(text.utf8)
        var scanner = AnthropicJSONSourceScanner(data: Data(bytes))
        let ranges = scanner.inputTokenRanges()

        #expect(ranges.count == 1)
        #expect(
            ranges.first.flatMap { String(bytes: bytes[$0], encoding: .utf8) }
                == "1e+2"
        )
    }

    @Test(
        "Malformed roots, collections, strings, numbers, literals, and trailing bytes are rejected",
        arguments: [
            "",
            "x",
            "tru",
            "falsex",
            "{",
            #"{"key"}"#,
            #"{"key":}"#,
            #"{"key":1,"#,
            "[",
            "[1",
            "[1,]",
            "[1,",
            #""unterminated"#,
            "-",
            "1.",
            "1e",
            "1e+",
            "01",
            "null trailing",
        ]
    )
    func malformedJSON(text: String) {
        var scanner = AnthropicJSONSourceScanner(data: Data(text.utf8))
        #expect(scanner.inputTokenRanges().isEmpty)
    }
}
