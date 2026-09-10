import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Adapter agent mail history")
struct AdapterAgentMessageHistoryTests {
    @Test("Agent mail becomes inbound user context, briefs arrive intact")
    func preparesAgentMessageHistory() throws {
        let body = Data(
            #"""
            {
              "model":"little-switch-route",
              "input":[
                {"type":"message","role":"user","content":[{"type":"input_text","text":"Spawn one agent."}]},
                {"type":"agent_message","id":"amsg_1","author":"/root","recipient":"/root/prenom_1",
                 "content":[
                   {"type":"input_text","text":"Message Type: NEW_TASK\nTask name: /root/prenom_1\nSender: /root\nPayload:\n"},
                   {"type":"encrypted_content","encrypted_content":"Invente un prénom aléatoire. Réponds uniquement avec le prénom."}
                 ]},
                {"type":"agent_message","id":"amsg_2","author":"/root/prenom_1","recipient":"/root",
                 "content":[{"type":"input_text","text":"Message Type: FINAL_ANSWER\nTask name: /root\nPayload:\nVeralune"}]},
                {"type":"agent_message","id":"amsg_3","author":"/root","recipient":"/root/prenom_2",
                 "content":[{"type":"input_text","text":""}]},
                {"type":"agent_message","id":"amsg_4","author":"/root","recipient":"/root/prenom_3",
                 "content":"raw string mail"},
                {"type":"agent_message","id":"amsg_5","author":"/root","recipient":"/root/prenom_4",
                 "content":[{"type":"attachment","file_id":"file_x"}]}
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
        #expect(messages.compactMap { $0["role"] as? String } == ["user", "user", "user"])
        #expect(messages[0]["content"] as? String == "Spawn one agent.")
        let brief = try #require(messages[1]["content"] as? String)
        #expect(brief.contains("Message Type: NEW_TASK"))
        #expect(brief.contains("Invente un prénom aléatoire. Réponds uniquement avec le prénom."))
        let answer = try #require(messages[2]["content"] as? String)
        #expect(answer.contains("Payload:\nVeralune"))
        #expect(prepared.droppedMailCount == 3)
    }
}
