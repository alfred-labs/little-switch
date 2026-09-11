import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI Responses remote compaction")
struct OpenAIResponsesRemoteCompactionTests {
    private func triggerBody() -> Data {
        Data(
            #"""
            {"model":"z.ai/glm-5.3","input":[
              {"type":"message","role":"user","content":[{"type":"input_text","text":"Long thread."}]},
              {"type":"compaction_trigger"}
            ],"stream":true}
            """#.utf8
        )
    }

    @Test("A terminal compaction trigger marks a compaction request")
    func detectsTrigger() throws {
        #expect(OpenAIResponsesRemoteCompaction.isCompactionRequest(triggerBody()))
        let plain = Data(
            #"{"model":"z.ai/glm-5.3","input":[{"type":"message","role":"user"}],"stream":true}"#.utf8
        )
        #expect(!OpenAIResponsesRemoteCompaction.isCompactionRequest(plain))
    }

    @Test("Buffering forces a non-streaming upstream request")
    func buffersUpstream() throws {
        let buffered = try OpenAIResponsesRemoteCompaction.bufferedObject(triggerBody())
        let object = try #require(
            JSONSerialization.jsonObject(with: buffered) as? [String: Any]
        )
        #expect(object["stream"] as? Bool == false)
        #expect(throws: OpenAIResponsesWebSearch.Error.self) {
            _ = try OpenAIResponsesRemoteCompaction.bufferedObject(Data("[1]".utf8))
        }
    }

    @Test("The provider's first message text becomes the summary")
    func extractsSummary() throws {
        let provider = Data(
            #"""
            {"id":"resp_1","output":[
              {"type":"reasoning"},
              {"type":"message","content":[{"type":"output_text","text":"Summary of the thread."}]}
            ]}
            """#.utf8
        )
        #expect(
            OpenAIResponsesRemoteCompaction.summary(fromProviderBody: provider)
                == "Summary of the thread."
        )
        #expect(
            OpenAIResponsesRemoteCompaction.summary(fromProviderBody: Data("{}".utf8)) == nil
        )
        // A message without parsable content parts carries no summary text.
        let malformed = Data(
            #"{"output":[{"type":"message","content":"not-parts"}]}"#.utf8
        )
        #expect(
            OpenAIResponsesRemoteCompaction.summary(fromProviderBody: malformed) == nil
        )
    }

    @Test("Payloads round-trip and foreign payloads stay opaque")
    func roundTripsPayload() throws {
        let payload = try OpenAIResponsesRemoteCompaction.payload(summary: "Thread summary.")
        #expect(
            OpenAIResponsesRemoteCompaction.summary(fromPayload: payload) == "Thread summary."
        )
        #expect(
            OpenAIResponsesRemoteCompaction.summary(fromPayload: #"{"type":"foreign"}"#) == nil
        )
        #expect(OpenAIResponsesRemoteCompaction.summary(fromPayload: nil) == nil)
    }

    @Test("The stream carries exactly one compaction item between lifecycle events")
    func buildsStream() throws {
        let body = try OpenAIResponsesRemoteCompaction.streamBody(
            responseID: "resp_compaction_1",
            model: "z.ai/glm-5.3",
            summary: "Thread summary.",
            createdAt: 42
        )
        let stream = try #require(String(data: body, encoding: .utf8))
        #expect(stream.contains("event: response.created\n"))
        #expect(stream.contains("event: response.output_item.added\n"))
        #expect(stream.contains("event: response.output_item.done\n"))
        #expect(stream.contains("event: response.completed\n"))
        #expect(stream.contains(#""type":"compaction""#))
        #expect(stream.contains("little_switch_compaction"))
        #expect(stream.contains("Thread summary."))
    }

    @Test("Replayed gateway compaction expands and foreign compaction drops")
    func replayConversion() throws {
        let payload = try OpenAIResponsesRemoteCompaction.payload(summary: "Earlier work.")
        let request: [String: Any] = [
            "model": "z.ai/glm-5.3",
            "stream": true,
            "input": [
                [
                    "type": "message", "role": "user",
                    "content": [["type": "input_text", "text": "Hi"]],
                ] as [String: Any],
                ["type": "compaction", "encrypted_content": payload] as [String: Any],
                ["type": "compaction", "encrypted_content": "gAAAAAB-foreign"] as [String: Any],
            ],
        ]
        let body = try JSONSerialization.data(withJSONObject: request)
        let normalized = try OpenAIResponsesNativeNamespacing.normalize(body)
        let object = try #require(
            JSONSerialization.jsonObject(with: normalized.body) as? [String: Any]
        )
        let items = try #require(object["input"] as? [[String: Any]])
        // The user message survives, the gateway payload expands into a
        // readable summary, and the foreign payload leaves the wire.
        #expect(items.count == 2)
        let summaryText =
            items.last.flatMap { $0["content"] as? [[String: Any]] }?
            .first?["text"] as? String
        #expect(summaryText?.contains("[Previous compaction summary]") == true)
        #expect(summaryText?.contains("Earlier work.") == true)
        #expect(!normalized.body.contains(Data("gAAAAAB-foreign".utf8)))
    }
}
