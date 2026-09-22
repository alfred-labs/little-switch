import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Anthropic image fallback content boundaries")
struct ImageFallbackContentBoundaryTests {
    @Test("Image fallback preserves every opaque field while replacing actual multimodal content")
    func preservesOpaqueFields() throws {
        let source = Data(
            #"""
            {"model":"route","max_tokens":16,
             "metadata":{"type":"image","path":"metadata.png"},
             "tools":[{"name":"render","input_schema":{"type":"object","examples":[{"type":"image","path":"schema.png"}]}}],
             "messages":[{"role":"assistant","content":[
               {"type":"tool_use","id":"call","name":"render","input":{"type":"image","path":"demo.png","nested":{"type":"image"}}}]},
               {"role":"user","content":[
                 {"type":"image","source":{"type":"url","url":"https://example.com/direct.png"}},
                 {"type":"tool_result","tool_use_id":"call","content":[
                   {"type":"text","text":"keep","extension":{"type":"image"}},
                   {"type":"image","source":{"type":"url","url":"https://example.com/tool.png"}},
                   {"type":"document","title":"Document","source":{"type":"content","content":[
                     {"type":"image","source":{"type":"url","url":"https://example.com/document.png"}}]}}]},
                 {"type":"vendor_content","content":[{"type":"image","path":"opaque.png"}]}]}]}
            """#.utf8)
        let replacement = try #require(try ImageFallback.replacingImages(in: source))
        let actual = try WireCodec.decode(JSONValue.self, from: replacement.body).value
        var expected = try #require(WireCodec.decode(JSONValue.self, from: source).value.object)
        var messages = try #require(expected["messages"]?.array)
        var user = try #require(messages[1].object)
        var content = try #require(user["content"]?.array)
        let notice: JSONValue = .object(["type": .string("text"), "text": .string(ImageFallback.notice)])
        content[0] = notice
        var result = try #require(content[1].object)
        var toolContent = try #require(result["content"]?.array)
        toolContent[1] = notice
        toolContent[2] = .object([
            "type": .string("document"), "title": .string("Document"),
            "source": .object(["type": .string("content"), "content": .array([notice])]),
        ])
        result["content"] = .array(toolContent)
        content[1] = .object(result)
        user["content"] = .array(content)
        messages[1] = .object(user)
        expected["messages"] = .array(messages)
        #expect(actual == .object(expected))
        #expect(replacement.didReplace)
    }

    @Test("Images inside fetched document content are omitted without changing document metadata")
    func fetchedDocumentImages() throws {
        let source = Data(
            #"""
            {"messages":[{"role":"user","content":[
              {"type":"web_fetch_tool_result","tool_use_id":"fetch","content":{
                "type":"web_fetch_result","url":"https://example.com/page","content":{
                  "type":"document","title":"Page","source":{"type":"content","content":[
                    {"type":"image","source":{"type":"url","url":"https://example.com/image.png"}}]}}}}]}]}
            """#.utf8)
        let replacement = try #require(try ImageFallback.replacingImages(in: source))
        let expected = Data(
            #"""
            {"messages":[{"role":"user","content":[
              {"type":"web_fetch_tool_result","tool_use_id":"fetch","content":{
                "type":"web_fetch_result","url":"https://example.com/page","content":{
                  "type":"document","title":"Page","source":{"type":"content","content":[
                    {"type":"text","text":"[Image omitted: the selected model does not accept image input.]"}]}}}}]}]}
            """#.utf8)
        #expect(try JSONValue.parse(replacement.body) == JSONValue.parse(expected))
    }

    @Test(
        "Image-shaped opaque data never triggers an image retry",
        arguments: [
            #"{"messages":[{"role":"assistant","content":[{"type":"tool_use","id":"call","name":"render","input":{"type":"image","path":"demo.png"}}]}]}"#,
            #"{"tools":[{"name":"render","input_schema":{"examples":[{"type":"image"}]}}]}"#,
            #"{"messages":[{"role":"user","content":[{"type":"unknown","content":[{"type":"image"}]}]}]}"#,
            #"{"messages":[{"role":"user","content":[{"type":"document","source":{"type":"text","content":[{"type":"image"}]}}]}]}"#,
            #"{"messages":[{"role":"user","content":{"type":"image"}}]}"#,
            #"[{"type":"image"}]"#,
        ])
    func opaqueDataDoesNotRetry(source: String) throws {
        let request = Data(source.utf8)
        #expect(try ImageFallback.replacingImages(in: request) == nil)
        #expect(
            !ImageFallback.shouldRetry(
                status: 400,
                responseBody: Data(
                    #"{"type":"error","error":{"type":"invalid_request_error","message":"Images unsupported"}}"#.utf8),
                originalRequest: request))
    }
}
