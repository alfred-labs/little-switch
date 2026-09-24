import Foundation
import Testing

@testable import LittleSwitchCore

struct ChatGPTConversationStartTests {
    @Test(arguments: [false, true])
    func nativeFirstMessageNeedsNoParent(nullParent: Bool) throws {
        // ChatGPT 26.917.71314 starts with currentNode == null. Its request
        // builder omits both conversation_id and parent_message_id.
        var object = try chatJSONObject(Self.nativeFirstMessage)
        if nullParent {
            object["conversation_id"] = NSNull()
            object["parent_message_id"] = NSNull()
        }
        let request = try ChatGPTConversationRequest.decode(JSONSerialization.data(withJSONObject: object))
        #expect(request.conversationID == nil)
        #expect(request.parentMessageID == nil)
        #expect(request.messages == [.init(id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", text: "hello")])
        #expect(!request.historyAndTrainingDisabled)
        let projected = try chatJSONObject(request.responsesBody(history: []))
        let expected = try chatJSONObject(
            Data(
                #"""
                {"model":"example:chat-model","stream":true,"store":false,"input":[
                  {"role":"user","content":[{"type":"input_text","text":"hello"}]}]}
                """#.utf8))
        #expect(projected as NSDictionary == expected as NSDictionary)
    }

    @Test(arguments: [false, true])
    func existingConversationStillRequiresParent(nullParent: Bool) throws {
        var object = try chatJSONObject(Self.nativeFirstMessage)
        object["conversation_id"] = "1e1771e5-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        if nullParent { object["parent_message_id"] = NSNull() }
        #expect(throws: ChatGPTConversationError.invalidRequest) {
            try ChatGPTConversationRequest.decode(JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test(arguments: ["", "not-uuid", "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"])
    func firstMessageRejectsMalformedOrCollidingExplicitParent(parent: String) throws {
        var object = try chatJSONObject(Self.nativeFirstMessage)
        object["parent_message_id"] = parent
        #expect(throws: ChatGPTConversationError.invalidRequest) {
            try ChatGPTConversationRequest.decode(JSONSerialization.data(withJSONObject: object))
        }
    }

    private static let nativeFirstMessage = Data(
        #"""
        {"source":"chat","action":"next","is_do_not_remember":false,
         "model":"example:chat-model","timezone":"Europe/Paris","timezone_offset_min":-120,
         "messages":[{"author":{"metadata":{},"name":null,"role":"user"},"channel":null,
           "content":{"content_type":"text","parts":["hello"]},"create_time":1790240400,
           "end_turn":null,"id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","metadata":{},
           "recipient":"all","status":"finished_successfully","update_time":null,"weight":1}],
         "supported_encodings":["v1"]}
        """#.utf8)
}
