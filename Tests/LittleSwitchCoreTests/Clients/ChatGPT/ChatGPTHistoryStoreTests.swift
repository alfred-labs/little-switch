import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("ChatGPT bounded history")
struct ChatGPTHistoryStoreTests {
    let owner = String(repeating: "a", count: 64)

    @Test func listOrdersByRecencyThenStableIdentifier() async throws {
        let store = try ChatGPTHistoryStore()
        var ids: [String] = []
        for now in [1.0, 3.0, 3.0, 2.0] {
            let turn = try await store.begin(request: historyRequest(), owner: owner, now: now)
            ids.append(turn.conversationID)
        }
        let expected = [ids[1], ids[2]].sorted() + [ids[3], ids[0]]
        #expect(await store.list(owner: owner, archived: false, starred: nil).map(\.id) == expected)
    }

    @Test func validatedUserOnlyHistoryHasNoDefaultModel() async throws {
        let store = try ChatGPTHistoryStore()
        let request = historyRequest()
        let turn = try await store.begin(request: request, owner: owner, now: 1)
        var value = try await store.conversation(id: turn.conversationID, owner: owner)
        value.nodes.removeValue(forKey: turn.assistantID)
        value.currentNodeID = request.messages[0].id
        try ChatGPTHistoryValidation.stored(value, key: value.id, limits: .default)
        let object = try chatJSONObject(value.nativeData())
        #expect(object["default_model_slug"] is NSNull)
        #expect(object["current_node"] as? String == value.currentNodeID)
        let mapping = try #require(object["mapping"] as? [String: [String: Any]])
        #expect(mapping[value.rootID]?["children"] as? [String] == [value.currentNodeID])
        let children = try #require(mapping[value.currentNodeID]?["children"] as? [String])
        #expect(children.isEmpty)
    }

    @Test("Two turns use complete trusted ancestry and retain edited branches")
    func ancestry() async throws {
        let store = try ChatGPTHistoryStore()
        let request = historyRequest(text: "  Hello\n world  ")
        let first = try await store.begin(request: request, owner: owner, now: 10)
        #expect(first.history.isEmpty)
        #expect(first.title == "Hello world")
        try await store.update(
            conversationID: first.conversationID, owner: owner, assistantID: first.assistantID, text: "answer")
        try await store.finish(
            conversationID: first.conversationID,
            owner: owner,
            assistantID: first.assistantID,
            status: .finishedSuccessfully,
            now: 11)
        let second = try await store.begin(
            request: historyRequest(conversation: first.conversationID, parent: first.assistantID, text: "again"),
            owner: owner,
            now: 12)
        #expect(
            second.history == [.init(role: .user, text: "  Hello\n world  "), .init(role: .assistant, text: "answer")])
        try await store.finish(
            conversationID: second.conversationID,
            owner: owner,
            assistantID: second.assistantID,
            status: .cancelled,
            now: 13)
        let branch = try await store.begin(
            request: historyRequest(conversation: first.conversationID, parent: request.parentMessageID, text: "edit"),
            owner: owner,
            now: 14)
        #expect(branch.history.isEmpty)
        let saved = try await store.conversation(id: first.conversationID, owner: owner)
        #expect(saved.nodes.count == 6)
        #expect(saved.currentNodeID == branch.assistantID)
        #expect(saved.nodes[second.assistantID]?.status == .cancelled)
    }

    @Test("Busy turns and account isolation prevent mutations")
    func isolation() async throws {
        let store = try ChatGPTHistoryStore()
        let first = try await store.begin(request: historyRequest(), owner: owner, now: 10)
        let otherOwner = String(repeating: "b", count: 64)
        await #expect(throws: ChatGPTHistoryError.notFound) {
            try await store.conversation(id: first.conversationID, owner: otherOwner)
        }
        await #expect(throws: ChatGPTHistoryError.notFound) {
            try await store.remove(id: first.conversationID, owner: otherOwner)
        }
        await #expect(throws: ChatGPTHistoryError.busy) {
            try await store.begin(
                request: historyRequest(conversation: first.conversationID, parent: first.assistantID),
                owner: owner,
                now: 11)
        }
        await #expect(throws: ChatGPTHistoryError.busy) {
            try await store.patch(id: first.conversationID, owner: owner, changes: .init(title: "new"), now: 11)
        }
        await #expect(throws: ChatGPTHistoryError.busy) {
            try await store.remove(id: first.conversationID, owner: owner)
        }
        #expect(await store.list(owner: otherOwner, archived: false, starred: nil).isEmpty)
    }

    @Test("Bounds reject growth without losing admitted messages")
    func bounds() async throws {
        let store = try ChatGPTHistoryStore(
            limits: .init(conversations: 1, nodesPerConversation: 2, textBytesPerConversation: 8))
        let first = try await store.begin(request: historyRequest(text: "hello"), owner: owner, now: 10)
        await #expect(throws: ChatGPTHistoryError.capacityExceeded) {
            try await store.update(
                conversationID: first.conversationID, owner: owner, assistantID: first.assistantID, text: "four")
        }
        try await store.update(
            conversationID: first.conversationID, owner: owner, assistantID: first.assistantID, text: "123")
        try await store.finish(
            conversationID: first.conversationID, owner: owner, assistantID: first.assistantID, status: .failed, now: 11
        )
        await #expect(throws: ChatGPTHistoryError.capacityExceeded) {
            try await store.begin(request: historyRequest(), owner: owner, now: 12)
        }
        await #expect(throws: ChatGPTHistoryError.capacityExceeded) {
            try await store.begin(
                request: historyRequest(conversation: first.conversationID, parent: first.assistantID),
                owner: owner,
                now: 12)
        }
        let saved = try await store.conversation(id: first.conversationID, owner: owner)
        #expect(saved.nodes[first.assistantID]?.text == "123")
        #expect(saved.nodes[first.assistantID]?.status == .failed)
        #expect(saved.nodes.count == 2)
    }
}

func historyRequest(
    conversation: String? = nil,
    parent: String? = UUID().uuidString.lowercased(),
    text: String = "hello",
    temporary: Bool = false,
    messageID: String = UUID().uuidString.lowercased()
) -> ChatGPTConversationRequest {
    ChatGPTConversationRequest(
        model: "fixture",
        conversationID: conversation,
        parentMessageID: parent,
        messages: [.init(id: messageID, text: text)],
        historyAndTrainingDisabled: temporary)
}
