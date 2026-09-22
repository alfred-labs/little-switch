import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Responses image budget content boundaries")
struct ResponsesImageBudgetBoundaryTests {
    @Test(
        "Tool output images get the same budget as message images",
        arguments: ["function_call_output", "custom_tool_call_output"])
    func toolOutputImages(type: String) throws {
        let input: [[String: Any]] = [
            [
                "type": type, "call_id": "call",
                "output": [["type": "input_image", "image_url": "https://example.com/image.png"]],
            ]
        ]
        let request: [String: Any] = [
            "input": input, "reasoning": ["effort": "high", "summary": "auto"],
            "metadata": ["keep": "value"],
        ]
        let actual = try #require(ResponsesImageTurnCompatibility.rewritten(request))
        let expected: [String: Any] = [
            "input": input, "reasoning": ["summary": "auto"], "max_output_tokens": 32_768,
            "metadata": ["keep": "value"],
        ]
        #expect(actual as NSDictionary == expected as NSDictionary)
    }

    @Test(
        "Budget detection shares message and opaque-content boundaries with image projection",
        arguments: [
            #"{"type":"function_call","arguments":{"type":"input_image"},"content":[{"type":"input_image"}]}"#,
            #"{"type":"custom_tool_call_output","output":{"type":"input_image"}}"#,
            #"{"type":"vendor_item","content":[{"type":"input_image"}]}"#,
            #"{"type":null,"role":"user","content":[{"type":"input_image"}]}"#,
            #"{"type":42,"role":"user","content":[{"type":"input_image"}]}"#,
        ])
    func opaqueImageShapes(item: String) throws {
        let body = Data((#"{"input":["# + item + #"],"reasoning":{"effort":"high"}}"#).utf8)
        let request = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(ResponsesImageTurnCompatibility.rewritten(request) == nil)
        let projection = try ResponsesImageInputProjection.project(body: body, acceptsImages: false)
        #expect(projection.body == body)
        #expect(projection.imageItemIndices.isEmpty)
    }

    @Test("Discriminator-free message images receive a budget")
    func easyMessageImages() throws {
        let request: [String: Any] = [
            "input": [["role": "user", "content": [["type": "input_image", "file_id": "file-image"]]]],
            "max_output_tokens": 512, "reasoning": ["effort": "high"],
        ]
        let actual = try #require(ResponsesImageTurnCompatibility.rewritten(request))
        #expect(actual["max_output_tokens"] as? Int == 512)
        #expect((actual["reasoning"] as? [String: String])?.isEmpty == true)
    }
}
