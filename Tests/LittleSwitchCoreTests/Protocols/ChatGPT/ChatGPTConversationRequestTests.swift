import Foundation
import Testing

@testable import LittleSwitchCore

struct ChatGPTConversationRequestTests {
    @Test func responseHistoryCountsPreviouslyStoredAndNewMessagesTogether() throws {
        let request = historyRequest()
        let history = Array(repeating: ChatGPTConversationTurn(role: .user, text: "a"), count: 256)
        #expect(throws: ChatGPTConversationError.limitExceeded) { try request.responsesBody(history: history) }
    }

    @Test func scalarToolContextIsRejected() throws {
        #expect(throws: ChatGPTConversationError.unsupportedRequest) {
            try ChatGPTRequestValidation.validateContext(["tools": false])
        }
    }
    @Test(arguments: ["not-json", "[]", "null", "{}"])
    func malformedBodyFailsWithSanitizedError(body: String) {
        #expect(throws: ChatGPTConversationError.invalidRequest) {
            try ChatGPTConversationRequest.decode(Data(body.utf8))
        }
    }

    @Test func acceptsOrdinaryNativeFieldsWithoutForwardingThem() throws {
        var object = try Self.baseObject()
        object["conversation_id"] = "1E1771E5-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
        object["conversation_mode"] = ["kind": "primary_assistant"]
        object["tools"] = [String]()
        object["tool_choice"] = NSNull()
        object["gizmo_id"] = NSNull()
        object["project_id"] = ""
        object["request_id"] = "private request"
        let request = try ChatGPTConversationRequest.decode(JSONSerialization.data(withJSONObject: object))
        #expect(request.conversationID == "1e1771e5-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
        let body = try #require(
            JSONSerialization.jsonObject(with: request.responsesBody(history: [])) as? [String: Any])
        #expect(Set(body.keys) == Set(["model", "input", "stream", "store"]))
    }
    @Test(arguments: [
        #"{"action":"continue"}"#, #"{"model":" "}"#, #"{"model":" padded "}"#,
        #"{"history_and_training_disabled":1}"#, #"{"history_and_training_disabled":"false"}"#,
        #"{"history_and_training_disabled":null}"#, #"{"conversation_id":"not-uuid"}"#,
        #"{"parent_message_id":false}"#, #"{"messages":[]}"#,
        #"{"tools":[{"type":"web_search"}]}"#, #"{"tool_choice":"auto"}"#,
        #"{"gizmo_id":"private"}"#, #"{"project_id":"private"}"#,
        #"{"gizmo_context":{"id":"private"}}"#, #"{"project_context":{"id":"private"}}"#,
        #"{"conversation_mode":{"kind":"canvas"}}"#, #"{"attachments":["private"]}"#,
    ])
    func rejectsUnsupportedRequests(patch: String) throws {
        var object = try Self.baseObject()
        object.merge(try #require(JSONSerialization.jsonObject(with: Data(patch.utf8)) as? [String: Any])) { _, new in
            new
        }
        #expect(throws: ChatGPTConversationError.self) {
            try ChatGPTConversationRequest.decode(JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test(arguments: [
        #"{"author":{"role":"assistant"}}"#, #"{"id":"not-uuid"}"#,
        #"{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}"#,
        #"{"content":{"content_type":"multimodal_text","parts":["x"]}}"#,
        #"{"content":{"content_type":"text","parts":[{}]}}"#,
        #"{"metadata":{"attachments":[{"id":"private"}]}}"#,
        #"{"metadata":"bad"}"#,
        #"{"content":{"content_type":"text","parts":["x"],"attachments":["private"]}}"#,
    ])
    func rejectsUnsupportedMessages(patch: String) throws {
        var object = try Self.baseObject()
        var messages = try #require(object["messages"] as? [[String: Any]])
        let changes = try #require(JSONSerialization.jsonObject(with: Data(patch.utf8)) as? [String: Any])
        messages[0].merge(changes) { _, new in new }
        object["messages"] = messages
        #expect(throws: ChatGPTConversationError.self) {
            try ChatGPTConversationRequest.decode(JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test func rejectsRepeatedIDsAndBoundsRequestsAndExpandedHistory() throws {
        var object = try Self.baseObject()
        let messages = try #require(object["messages"] as? [[String: Any]])
        object["messages"] = messages + messages
        #expect(throws: ChatGPTConversationError.invalidRequest) {
            try ChatGPTConversationRequest.decode(JSONSerialization.data(withJSONObject: object))
        }
        object["messages"] = (0..<9).map { index in
            var message = messages[0]
            message["id"] = "bbbbbbbb-bbbb-4bbb-8bbb-\(String(format: "%012d", index))"
            return message
        }
        #expect(throws: ChatGPTConversationError.limitExceeded) {
            try ChatGPTConversationRequest.decode(JSONSerialization.data(withJSONObject: object))
        }
        #expect(throws: ChatGPTConversationError.limitExceeded) {
            try ChatGPTConversationRequest.decode(Data(repeating: 0x20, count: 8 * 1_024 * 1_024 + 1))
        }
        let request = try ChatGPTConversationRequest.decode(JSONSerialization.data(withJSONObject: Self.baseObject()))
        #expect(!request.historyAndTrainingDisabled)
        #expect(throws: ChatGPTConversationError.limitExceeded) {
            try request.responsesBody(history: [
                .init(role: .assistant, text: String(repeating: "a", count: 4 * 1_024 * 1_024))
            ])
        }
    }

    private static func baseObject() throws -> [String: Any] {
        try #require(
            JSONSerialization.jsonObject(
                with: Data(
                    #"""
                    {"action":"next","model":"vendor:model","parent_message_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                     "messages":[{"id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","author":{"role":"user"},
                       "content":{"content_type":"text","parts":["hello"]}}]}
                    """#.utf8)) as? [String: Any])
    }
    @Test func validatesNativeRequestAndProjectsOnlyTrustedText() throws {
        let request = try ChatGPTConversationRequest.decode(
            Data(
                #"""
                {"action":"next","model":"vendor:model","parent_message_id":"AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA",
                 "messages":[{"id":"BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB","author":{"role":"user"},
                   "content":{"content_type":"text","parts":["  Bonjour 🐈\n","suite"]},"metadata":{}}],
                 "history_and_training_disabled":true,"timezone":"Europe/Paris","locale":"fr","telemetry":{"private":"discard"}}
                """#.utf8))
        #expect(request.parentMessageID == "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
        #expect(request.messages == [.init(id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", text: "  Bonjour 🐈\nsuite")])
        #expect(request.historyAndTrainingDisabled)
        #expect(request.conversationID == nil)
        let body = try request.responsesBody(history: [
            .init(role: .user, text: "earlier"), .init(role: .assistant, text: "answer"),
        ])
        let expected = Data(
            #"""
            {"model":"vendor:model","stream":true,"store":false,"input":[
              {"role":"user","content":[{"type":"input_text","text":"earlier"}]},
              {"role":"assistant","content":[{"type":"output_text","text":"answer","annotations":[]}]},
              {"role":"user","content":[{"type":"input_text","text":"  Bonjour 🐈\nsuite"}]}]}
            """#.utf8)
        #expect(
            try JSONSerialization.jsonObject(with: body) as? NSDictionary == JSONSerialization.jsonObject(
                with: expected) as? NSDictionary)
    }
}
