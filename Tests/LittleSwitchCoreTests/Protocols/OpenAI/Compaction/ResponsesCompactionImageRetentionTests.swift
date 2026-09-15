import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Compaction preserves uninspected images")
struct CompactionImageRetentionTests {
    @Test("A text summary must retain a consumed tool image and its call", arguments: [false, true])
    func forcedRetention(custom: Bool) throws {
        let original = history(custom: custom)
        let plan = try ResponsesCompactionFixture.plan(items: original)
        #expect(plan.imageItemIndices == [1])
        let text = try plan.preservingUninspectedImages()
        let result = try text.complete(responseBody: ResponsesCompactionFixture.response())
        let payload = try ResponsesCompactionFixture.payload(result)
        #expect(
            try ResponsesCompactionFixture.data(payload["retained"] as Any)
                == ResponsesCompactionFixture.data(Array(original.prefix(2))))
        #expect(text.items == plan.items)
        let request = try text.summaryRequest(model: "text", stream: false, acceptsImages: false)
        let fields = try ResponsesCompactionFixture.object(request)
        let rendered = try ResponsesCompactionFixture.text(fields["input"] as Any)
        #expect(!rendered.contains(Self.imageURL))
        #expect(rendered.contains(ResponsesImageInputProjection.omissionText))
        #expect((fields["instructions"] as? String)?.contains("do not claim to have inspected it") == true)
        let vision = try plan.summaryRequest(model: "vision", stream: false)
        #expect(
            try ResponsesCompactionFixture.text(ResponsesCompactionFixture.object(vision)["input"] as Any).contains(
                Self.imageURL))
    }

    @Test("A second text compaction still allows the original image on a later vision turn")
    func roundTrip() throws {
        let original = history()
        let first = try ResponsesCompactionFixture.plan(items: original).preservingUninspectedImages()
        let one = try first.complete(responseBody: ResponsesCompactionFixture.response())
        let checkpoint = try ResponsesCompactionFixture.object(one.itemJSON)
        let second = try ResponsesCompactionFixture.plan(items: [checkpoint, original[2]]).preservingUninspectedImages()
        let two = try second.complete(responseBody: ResponsesCompactionFixture.response())
        let payload = try ResponsesCompactionFixture.payload(two)
        #expect(
            try ResponsesCompactionFixture.data(payload["retained"] as Any)
                == ResponsesCompactionFixture.data(Array(original.prefix(2))))
        let expanded = try #require(
            try ResponsesCompactionPayload.expand(item: ResponsesCompactionFixture.object(two.itemJSON)))
        let body = try ResponsesCompactionFixture.data(["model": "vision", "input": expanded])
        let projected = try ResponsesImageInputProjection.project(body: body, acceptsImages: true)
        #expect(projected.body == body)
        #expect(projected.imageItemIndices.count == 1)
    }

    @Test("An overflow before image rejection cannot trim an image or its dependency closure")
    func overflow() throws {
        let original = history()
        var plan = try ResponsesCompactionFixture.plan(
            items: Array(original.prefix(2)) + [
                ["type": "message", "role": "assistant", "content": String(repeating: "Old text.", count: 1_000)],
                original[2], ResponsesCompactionFixture.message,
            ])
        #expect(try plan.trimForContextLimit() > 0)
        #expect(plan.omittedIndices.isDisjoint(with: [0, 1]))
        let text = try plan.preservingUninspectedImages()
        let result = try text.complete(responseBody: ResponsesCompactionFixture.response())
        #expect(
            try ResponsesCompactionFixture.data(ResponsesCompactionFixture.payload(result)["retained"] as Any)
                == ResponsesCompactionFixture.data(Array(original.prefix(2))))
        var protectedOnly = try ResponsesCompactionFixture.plan(items: original)
        #expect(try protectedOnly.trimForContextLimit() == 0)
    }

    @Test("Message images and file references survive without exposing an attachment to a text model")
    func fileReferences() throws {
        let message: [String: Any] = [
            "role": "user", "content": [["type": "input_image", "file_id": "file-original"]],
        ]
        let plan = try ResponsesCompactionFixture.plan(items: [message]).preservingUninspectedImages()
        let result = try plan.complete(responseBody: ResponsesCompactionFixture.response())
        #expect(
            try ResponsesCompactionFixture.data(ResponsesCompactionFixture.payload(result)["retained"] as Any)
                == ResponsesCompactionFixture.data([message]))
        let projected = try ResponsesImageInputProjection.project(
            body: plan.summaryRequest(model: "text", stream: false, acceptsImages: false), acceptsImages: true)
        #expect(projected.imageItemIndices.isEmpty)
    }

    @Test("Oversized retained checkpoints fail explicitly rather than losing source data")
    func checkpointBound() throws {
        let plan = try ResponsesCompactionFixture.plan(items: history()).preservingUninspectedImages()
        #expect(throws: ResponsesCompactionError.responseTooLarge) {
            try plan.complete(responseBody: ResponsesCompactionFixture.response(), maximumBytes: 64)
        }
        #expect(try plan.complete(responseBody: ResponsesCompactionFixture.response()).itemJSON.count > 64)
    }

    @Test("Image-shaped unknown fields are data, not attachments")
    func unknownFields() throws {
        var original = history()
        original[0]["content"] = [["type": "input_image", "image_url": "https://unknown.example/data"]]
        let plan = try ResponsesCompactionFixture.plan(items: original)
        let text = try plan.summaryRequest(model: "text", stream: false, acceptsImages: false)
        #expect(
            try ResponsesCompactionFixture.text(ResponsesCompactionFixture.object(text)["input"] as Any)
                .contains("https://unknown.example/data"))
    }

    private func history(custom: Bool = false) -> [[String: Any]] {
        [
            [
                "type": custom ? "custom_tool_call" : "function_call", "call_id": "image", "name": "view_image",
                custom ? "input" : "arguments": "{}",
            ],
            [
                "type": custom ? "custom_tool_call_output" : "function_call_output", "call_id": "image",
                "output": [["type": "input_image", "image_url": Self.imageURL]],
            ],
            ["type": "message", "role": "assistant", "content": "I inspected the previous result."],
        ]
    }

    private static let imageURL = "data:image/png;base64,b3JpZ2luYWw="
}
