import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Diagnostic JSON identity")
struct DiagnosticJSONTests {
    @Test(
        "Canonical JSON retains Python numeric kinds and rounding",
        arguments: [
            (
                #"[18446744073709551617,18446744073709551617.0]"#,
                #"[18446744073709551617, 1.8446744073709552e+19]"#
            ),
            (#"[1.00000000000000000001,1.00000000000000000002,1e0]"#, "[1.0, 1.0, 1.0]"),
            ("[0,-0,0.0,-0.0]", "[0, 0, 0.0, -0.0]"),
            ("[1E+4,-7]", "[10000.0, -7]"),
            (
                "[-9.26069097146235200e+15,9.57335435644351000e+15,9.999999999999998e15,1e16]",
                "[-9260690971462352.0, 9573354356443510.0, 9999999999999998.0, 1e+16]"
            ),
            (
                "[1.0000000000000005e15,1.00000000000000025e15,1.000000000000000125e15]",
                "[1000000000000000.5, 1000000000000000.2, 1000000000000000.1]"
            ),
            ("[1e400,-1e400]", "[Infinity, -Infinity]"),
            (String(repeating: "9", count: 201), String(repeating: "9", count: 201)),
            (
                #" {"b": [], "a": {}, "b": [true,false,null,"1e0"]} "#,
                #"{"a": {}, "b": [true, false, null, "1e0"]}"#
            ),
            (#"{"é":1,"e\u0301":2}"#, #"{"e\u0301": 2, "\u00e9": 1}"#),
            (
                #"["\b\f\n\r\t\u007f","\\\"/😀"]"#,
                #"["\b\f\n\r\t\u007f", "\\\"/\ud83d\ude00"]"#
            ),
        ])
    func canonical(pair: (String, String)) throws {
        #expect(try DiagnosticMessagePrefix.encode(DiagnosticJSONReader.read(Data(pair.0.utf8))) == pair.1)
    }

    @Test(
        "Malformed numbers and incomplete JSON cannot become a conversation key",
        arguments: [
            "", "01", "1.", "1e", "--1", "[1 2]", "[1,]", "{\"x\" 1}", "{\"x\":1,}", "true false",
            "[", "{", "\"unterminated", "\"\\q\"", "tru", "nul", "[+1]", "{1:2}", "-",
            "{\"x\":1 \"y\":2}", "{\"x\":1",
        ])
    func invalid(source: String) {
        #expect(throws: (any Error).self) {
            try DiagnosticJSONReader.read(Data(source.utf8))
        }
    }

    @Test("Malformed deeply nested input is bounded without consuming the process stack")
    func depthLimit() {
        let source = String(repeating: "[", count: 512) + "0" + String(repeating: "]", count: 512)
        #expect(throws: (any Error).self) { try DiagnosticJSONReader.read(Data(source.utf8)) }
    }
}
