import Foundation
import Testing

@testable import LittleSwitchCore

struct ChatGPTHistoryParentTests {
    @Test func messageIdentifiersRetryCollisionsAndKeepAvailableCandidates() throws {
        let candidate = try #require(UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"))
        let canonical = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        #expect(ChatGPTHistoryMessageID.make(excluding: [], startingWith: candidate) == canonical)
        let occupied: Set<String> = [canonical, "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"]
        let replacement = ChatGPTHistoryMessageID.make(excluding: occupied, startingWith: candidate)
        #expect(UUID(uuidString: replacement)?.uuidString.lowercased() == replacement)
        #expect(!occupied.contains(replacement))
    }

    @Test func missingParentCannotResetAnExistingConversation() async throws {
        let directory = historyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.json")
        let owner = String(repeating: "a", count: 64)
        let store = try ChatGPTHistoryStore(fileURL: file)
        let first = try await store.begin(request: historyRequest(parent: nil), owner: owner, now: 1)
        try await store.finish(
            conversationID: first.conversationID,
            owner: owner,
            assistantID: first.assistantID,
            status: .finishedSuccessfully,
            now: 2)
        let before = try await store.conversation(id: first.conversationID, owner: owner)
        let bytes = try Data(contentsOf: file)

        for parent in [nil, "invalid", UUID().uuidString.lowercased()] {
            await #expect(throws: ChatGPTHistoryError.invalidInput) {
                try await store.begin(
                    request: historyRequest(conversation: first.conversationID, parent: parent), owner: owner, now: 3)
            }
            #expect(try await store.conversation(id: first.conversationID, owner: owner) == before)
            #expect(try Data(contentsOf: file) == bytes)
        }
        let second = try await store.begin(
            request: historyRequest(conversation: first.conversationID, parent: first.assistantID, text: "again"),
            owner: owner,
            now: 4)
        #expect(second.history == [.init(role: .user, text: "hello"), .init(role: .assistant, text: "")])
        #expect(try await store.conversation(id: first.conversationID, owner: owner).rootID == before.rootID)
    }
}
