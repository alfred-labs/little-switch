import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Adapter image input")
struct AdapterImageInputTests {
    @Test("Mixed text and image parts become chat-completions multipart content")
    func convertsMultipartMessage() throws {
        let body = Data(
            #"""
            {
              "model":"little-switch-route",
              "input":[
                {"type":"message","role":"user","content":[
                  {"type":"input_text","text":"C'est quoi ce screenshot"},
                  {"type":"input_image","image_url":"data:image/png;base64,aGVsbG8="}
                ]}
              ]
            }
            """#.utf8
        )

        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: body,
            targetModel: "glm-5.3-flash"
        )
        let request =
            try #require(
                try JSONSerialization.jsonObject(with: prepared.upstreamBody) as? [String: Any]
            )
        let messages = try #require(request["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? [[String: Any]])

        #expect(content.count == 2)
        #expect(content[0]["type"] as? String == "text")
        #expect(content[0]["text"] as? String == "C'est quoi ce screenshot")
        #expect(content[1]["type"] as? String == "image_url")
        let image = try #require(content[1]["image_url"] as? [String: Any])
        #expect(try #require(image["url"] as? String) == "data:image/png;base64,aGVsbG8=")
    }

    @Test("An image without a usable URL is rejected before dispatch")
    func rejectsUnusableImage() {
        let body = Data(
            #"""
            {
              "model":"little-switch-route",
              "input":[
                {"type":"message","role":"user","content":[
                  {"type":"input_image","detail":"auto"}
                ]}
              ]
            }
            """#.utf8
        )

        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
            try OpenAIResponsesChatCompletions.prepare(
                body: body,
                targetModel: "glm-5.3-flash"
            )
        }
    }

    @Test("Unsupported content parts inside a message are rejected")
    func rejectsUnknownParts() {
        let body = Data(
            #"""
            {
              "model":"little-switch-route",
              "input":[
                {"type":"message","role":"user","content":[
                  {"type":"input_audio","audio_url":"data:audio/wav;base64,aGVsbG8="}
                ]}
              ]
            }
            """#.utf8
        )

        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
            try OpenAIResponsesChatCompletions.prepare(
                body: body,
                targetModel: "glm-5.3-flash"
            )
        }
    }
}
