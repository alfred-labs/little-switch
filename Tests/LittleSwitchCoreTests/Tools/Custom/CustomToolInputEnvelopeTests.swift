import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Custom tool input envelope")
struct CustomToolInputEnvelopeTests {
    @Test("Owned input text survives the single-field JSON envelope byte for byte")
    func preservesInputBytes() throws {
        let inputs = [
            "",
            "\r\n",
            "back\\slash \"quote\"",
            "é🙂",
            "e\u{0301}",
            "\u{0000}\t\u{001F}",
            #"{"input":"not the envelope"}"#,
        ]
        for input in inputs {
            let arguments = try CustomToolInputEnvelope.encode(input)
            let decoded = try CustomToolInputEnvelope.decode(arguments)
            #expect(Array(decoded.utf8) == Array(input.utf8))
        }
    }

    @Test("Encoding uses exactly the owned input key")
    func encodedShape() throws {
        #expect(try CustomToolInputEnvelope.encode("") == #"{"input":""}"#)
    }

    @Test("Escaped key and value representations decode to the same text")
    func acceptsEscapedRepresentations() throws {
        #expect(try CustomToolInputEnvelope.decode(#"{ "\u0069nput": "A" }"#) == "A")
        #expect(try CustomToolInputEnvelope.decode(#"{ "input": "\u0041" }"#) == "A")
        #expect(try CustomToolInputEnvelope.decode(" \t\r\n{\n\t\"input\"\r : \"ok\"\n}\t \r\n") == "ok")
    }

    @Test("Rejects envelope shapes that are not one strict input string")
    func rejectsInvalidEnvelopes() {
        let invalid = [
            "", " \t\r\n", "{}", "{", #"{"input""#, #"{"input":"#, #"{"input": "x""#,
            #"{"input" "x"}"#, #"{"wrong":"x"}"#, #"{"input":"x",}"#, #"{"input":"x"}{}"#,
            #"{"input":"\q"}"#, #"{"input":"abc\"#, "{\"input\":\"raw\nline\"}",
            #"{"input":"a","input":"b"}"#,
            #"{ "\u0069nput":"a", "input":"b" }"#,
            #"{"input":{"nested":[1,"escaped\\\"text"]},"input":"x"}"#,
            #"{"input":"x","extra":1}"#,
            #"{"extra":1,"input":"x"}"#,
            #"{"input":null}"#,
            #"{"input":1}"#,
            #"{"input":{"value":"x"}}"#,
            #"[{"input":"x"}]"#,
            #"{"input":"x"} trailing"#,
            #"{"input":"\ud800"}"#,
            #"{"input":"abc"#,
        ]
        for arguments in invalid {
            #expect(throws: CustomToolInputEnvelope.Error.invalidEnvelope) {
                try CustomToolInputEnvelope.decode(arguments)
            }
        }
    }
}
