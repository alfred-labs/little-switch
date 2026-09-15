import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Responses image input projection")
struct ResponsesImageInputProjectionTests {
    @Test("Text projection edits only actual image parts and preserves exact unrelated JSON values")
    func copyProjection() throws {
        let body = Data(
            #"""
            {"model":"route","large":18446744073709551615,"tiny":1.230000000000000001e-999,
             "tools":[{"type":"function","name":"f","parameters":{"type":"input_image","image_url":"schema"}}],
             "input":[
               {"role":"user","content":[{"type":"input_text","text":"hello"},{"type":"input_image","image_url":"data:image/png;base64,aGVsbG8="}]},
               {"type":"function_call","call_id":"c","name":"f","arguments":"{\"type\":\"input_image\",\"image_url\":\"argument\"}"},
               {"type":"function_call_output","call_id":"c","output":[{"type":"input_image","file_id":"file-image"}]},
               {"type":"custom_tool_call_output","call_id":"d","output":"{\"type\":\"input_image\"}"},
               {"type":"unknown","content":[{"type":"input_image","image_url":"unknown"}]}]}
            """#.utf8)
        let original = body
        let projected = try ResponsesImageInputProjection.project(body: body, acceptsImages: false)
        #expect(projected.imageItemIndices == [0, 2])
        #expect(projected.omittedImageCount == 2)
        #expect(body == original)
        var expected = try #require(WireCodec.decode(JSONValue.self, from: original).value.object)
        var items = try #require(expected["input"]?.array)
        var message = try #require(items[0].object)
        var content = try #require(message["content"]?.array)
        let notice: JSONValue = .object([
            "type": .string("input_text"), "text": .string(ResponsesImageInputProjection.omissionText),
        ])
        content[1] = notice
        message["content"] = .array(content)
        items[0] = .object(message)
        var output = try #require(items[2].object)
        output["output"] = .array([notice])
        items[2] = .object(output)
        expected["input"] = .array(items)
        #expect(try WireCodec.decode(JSONValue.self, from: projected.body).value == .object(expected))
        let vision = try ResponsesImageInputProjection.project(body: original, acceptsImages: true)
        #expect(vision.body == original)
        #expect(vision.imageItemIndices == [0, 2])
        #expect(vision.omittedImageCount == 0)
    }

    @Test("Plain input and non-multimodal tool JSON stay byte-for-byte unchanged")
    func noImages() throws {
        for text in [
            #"{"input":"literal input_image"}"#,
            #"{"input":[{"type":"function_call_output","output":{"type":"input_image","image_url":"JSON data"}}]}"#,
            #"{"input":[{"type":"message","role":"user","content":"{\"type\":\"input_image\"}"}]}"#,
        ] {
            let body = Data(text.utf8)
            let result = try ResponsesImageInputProjection.project(body: body, acceptsImages: false)
            #expect(result.body == body)
            #expect(result.imageItemIndices.isEmpty)
            #expect(result.omittedImageCount == 0)
        }
    }
}
