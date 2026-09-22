import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Responses EasyInputMessage Chat projection")
struct ResponsesEasyInputMessageTests {
    @Test(
        "An omitted message discriminator accepts each supported role",
        arguments: ["user", "assistant", "system", "developer"])
    func omittedType(role: String) throws {
        var messages: [[String: Any]] = []
        let count = try ResponsesChatCompletionsHistory.append(
            [["role": role, "content": "Hi"]], to: &messages, bindings: [:])
        #expect(count == 0)
        #expect(messages as NSArray == [["role": role == "developer" ? "system" : role, "content": "Hi"]] as NSArray)
    }

    @Test("An omitted message discriminator accepts structured text and images")
    func omittedTypeMultipart() throws {
        var messages: [[String: Any]] = []
        _ = try ResponsesChatCompletionsHistory.append(
            [
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": "Look"],
                        ["type": "input_image", "image_url": "https://example.com/image.png", "detail": "low"],
                    ],
                ]
            ],
            to: &messages,
            bindings: [:])
        let expected: [[String: Any]] = [
            [
                "role": "user",
                "content": [
                    ["type": "text", "text": "Look"],
                    ["type": "image_url", "image_url": ["url": "https://example.com/image.png", "detail": "low"]],
                ],
            ]
        ]
        #expect(messages as NSArray == expected as NSArray)
    }

    @Test(
        "A present invalid discriminator is never treated as an omitted one",
        arguments: ["null", "42", "true", "{}", "[]", "\"\"", #""unknown""#])
    func invalidPresentType(type: String) throws {
        let source = Data((#"[{"type":"# + type + #", "role":"user","content":"Hi"}]"#).utf8)
        let input = try JSONSerialization.jsonObject(with: source)
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
            var messages: [[String: Any]] = []
            _ = try ResponsesChatCompletionsHistory.append(input, to: &messages, bindings: [:])
        }
    }

    @Test(
        "Discriminator-free messages still require valid role and content",
        arguments: [
            #"{"content":"Hi"}"#, #"{"role":"tool","content":"Hi"}"#,
            #"{"role":null,"content":"Hi"}"#, #"{"role":"user"}"#,
            #"{"role":"user","content":null}"#, #"{"role":"user","content":42}"#,
            #"{"role":"user","content":[{"type":"input_text","text":false}]}"#,
        ])
    func malformedEasyMessage(item: String) throws {
        let input = try JSONSerialization.jsonObject(with: Data(("[" + item + "]").utf8))
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
            var messages: [[String: Any]] = []
            _ = try ResponsesChatCompletionsHistory.append(input, to: &messages, bindings: [:])
        }
    }
}
