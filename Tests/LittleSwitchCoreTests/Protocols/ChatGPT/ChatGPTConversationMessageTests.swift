import Foundation
import Testing

@testable import LittleSwitchCore

struct ChatGPTConversationMessageTests {
    @Test func messageEncodingRejectsNonfiniteTimestampsAndInvalidIDs() {
        #expect(throws: ChatGPTConversationError.invalidRequest) {
            try ChatGPTNativeMessage.user(
                message: .init(id: "not-uuid", text: "x"),
                parentID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                timestamp: 123)
        }
        #expect(throws: ChatGPTConversationError.invalidRequest) {
            try ChatGPTNativeMessage.assistant(
                identity: Self.identity,
                model: "vendor:model",
                text: "x",
                timestamp: .nan,
                status: .inProgress)
        }
    }
    @Test func assistantSnapshotUsesNativeShapeAndStableTimestamps() throws {
        let data = try ChatGPTNativeMessage.assistant(
            identity: Self.identity,
            model: "vendor:model",
            text: "Bonjour 🐈",
            timestamp: 123,
            status: .finishedSuccessfully,
            updateTimestamp: 124)
        let expected = Data(
            #"""
            {"id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","author":{"role":"assistant","name":null,"metadata":{}},
             "create_time":123,"update_time":124,"content":{"content_type":"text","parts":["Bonjour 🐈"]},
             "status":"finished_successfully","end_turn":true,"weight":1,"recipient":"all","channel":"final",
             "metadata":{"model_slug":"vendor:model","parent_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
               "finish_details":{"type":"stop","stop_tokens":[]}}}
            """#.utf8)
        #expect(
            try JSONSerialization.jsonObject(with: data) as? NSDictionary == JSONSerialization.jsonObject(
                with: expected) as? NSDictionary)
    }

    @Test(arguments: [ChatGPTNativeMessage.Status.inProgress, .failed, .cancelled])
    func unsuccessfulStatusNeverClaimsFinishedSuccessfully(status: ChatGPTNativeMessage.Status) throws {
        let data = try ChatGPTNativeMessage.assistant(
            identity: Self.identity,
            model: "vendor:model",
            text: "partial",
            timestamp: 123,
            status: status)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["status"] as? String == status.rawValue)
        #expect(object["end_turn"] as? Bool == (status != .inProgress))
        #expect((object["metadata"] as? [String: Any])?["finish_details"] == nil)
        #expect(object["create_time"] as? Int == object["update_time"] as? Int)
    }

    @Test func userMessageHasNormalizedIdentityAndCompletedText() throws {
        let data = try ChatGPTNativeMessage.user(
            message: .init(id: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB", text: "  question\n"),
            parentID: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA",
            timestamp: 123)
        let expected = Data(
            #"""
            {"id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","author":{"role":"user","name":null,"metadata":{}},
             "create_time":123,"update_time":123,"content":{"content_type":"text","parts":["  question\n"]},
             "status":"finished_successfully","end_turn":true,"weight":1,"recipient":"all","channel":"final",
             "metadata":{"parent_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}}
            """#.utf8)
        #expect(
            try JSONSerialization.jsonObject(with: data) as? NSDictionary == JSONSerialization.jsonObject(
                with: expected) as? NSDictionary)
    }

    private static let identity = ChatGPTNativeMessage.Identity(
        id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", parentID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")

    @Test func ownedConversationIDsRequireAValidReservedUUID() {
        let generated = ChatGPTConversationID.make()
        #expect(ChatGPTConversationID.isOwned(generated))
        #expect(ChatGPTConversationID.isOwned("1E1771E5-AAAA-4AAA-8AAA-AAAAAAAAAAAA"))
        #expect(!ChatGPTConversationID.isOwned("1e1771e5-not-a-uuid"))
        #expect(!ChatGPTConversationID.isOwned("prefix1e1771e5-aaaa-4aaa-8aaa-aaaaaaaaaaaa"))
        #expect(!ChatGPTConversationID.isOwned("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"))
    }
}
