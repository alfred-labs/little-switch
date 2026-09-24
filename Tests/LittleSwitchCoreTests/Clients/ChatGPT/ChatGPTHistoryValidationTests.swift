import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("ChatGPT history validation")
struct ChatGPTHistoryValidationTests {
    let owner = String(repeating: "a", count: 64)

    @Test func updatesCannotReviveACompletedAssistant() async throws {
        let store = try ChatGPTHistoryStore()
        let turn = try await store.begin(request: historyRequest(), owner: owner, now: 1)
        try await store.finish(
            conversationID: turn.conversationID,
            owner: owner,
            assistantID: turn.assistantID,
            status: .finishedSuccessfully,
            now: 2)
        let before = try await store.conversation(id: turn.conversationID, owner: owner)
        await #expect(throws: ChatGPTHistoryError.invalidInput) {
            try await store.update(
                conversationID: turn.conversationID, owner: owner, assistantID: turn.assistantID, text: "late")
        }
        #expect(try await store.conversation(id: turn.conversationID, owner: owner) == before)
    }

    @Test(arguments: ["user-status", "user-model", "cycle"])
    func invalidUserNodesAndCyclesCannotLoad(mutation: String) async throws {
        let store = try ChatGPTHistoryStore()
        let request = historyRequest()
        let turn = try await store.begin(request: request, owner: owner, now: 1)
        var value = try await store.conversation(id: turn.conversationID, owner: owner)
        let user = try #require(value.nodes[request.messages[0].id])
        value.nodes[user.id] = ChatGPTHistoryNode(
            id: user.id,
            parentID: mutation == "cycle" ? turn.assistantID : user.parentID,
            role: .user,
            text: user.text,
            model: mutation == "user-model" ? "invalid" : nil,
            createdAt: 1,
            updatedAt: 1,
            status: mutation == "user-status" ? .failed : .finishedSuccessfully)
        #expect(throws: ChatGPTHistoryError.invalidStorage) {
            try ChatGPTHistoryValidation.stored(value, key: value.id, limits: .init())
        }
    }

    @Test("Reserved admission IDs, node collisions, and temporary flags are checked")
    func identifiers() async throws {
        let store = try ChatGPTHistoryStore()
        let id = ChatGPTConversationID.make()
        let request = historyRequest()
        let first = try await store.begin(request: request, owner: owner, now: 10, newConversationID: id)
        #expect(first.conversationID == id)
        try await store.finish(
            conversationID: id, owner: owner, assistantID: first.assistantID, status: .cancelled, now: 11)
        await #expect(throws: ChatGPTHistoryError.invalidInput) {
            try await store.begin(request: historyRequest(), owner: owner, now: 12, newConversationID: id)
        }
        await #expect(throws: ChatGPTHistoryError.invalidInput) {
            try await store.begin(
                request: historyRequest(), owner: owner, now: 12, newConversationID: UUID().uuidString)
        }
        await #expect(throws: ChatGPTHistoryError.invalidInput) {
            try await store.begin(
                request: historyRequest(conversation: id, parent: first.assistantID, messageID: request.messages[0].id),
                owner: owner,
                now: 12)
        }
        await #expect(throws: ChatGPTHistoryError.invalidInput) {
            try await store.begin(
                request: historyRequest(conversation: id, parent: first.assistantID, temporary: true),
                owner: owner,
                now: 12)
        }
        await #expect(throws: ChatGPTHistoryError.invalidInput) {
            try await store.begin(
                request: historyRequest(conversation: id, parent: first.assistantID),
                owner: owner,
                now: 12,
                newConversationID: id)
        }
        await #expect(throws: ChatGPTHistoryError.invalidInput) {
            try await store.begin(request: historyRequest(), owner: "bad-owner", now: 12)
        }
        await #expect(throws: ChatGPTHistoryError.notFound) {
            try await store.begin(request: historyRequest(conversation: UUID().uuidString), owner: owner, now: 12)
        }
    }

    @Test("Patch filters, invalid nodes and titles, and removal are account scoped")
    func patches() async throws {
        let store = try ChatGPTHistoryStore()
        let request = historyRequest()
        let turn = try await store.begin(request: request, owner: owner, now: 10)
        try await store.finish(
            conversationID: turn.conversationID,
            owner: owner,
            assistantID: turn.assistantID,
            status: .finishedSuccessfully,
            now: 11)
        for changes in [
            ChatGPTHistoryPatch(title: "  "), .init(title: String(repeating: "x", count: 257)),
            .init(currentNodeID: UUID().uuidString),
        ] {
            await #expect(throws: ChatGPTHistoryError.invalidInput) {
                try await store.patch(id: turn.conversationID, owner: owner, changes: changes, now: 12)
            }
        }
        try await store.patch(
            id: turn.conversationID,
            owner: owner,
            changes: .init(title: "  Renamed  ", archived: true, starred: true, currentNodeID: request.parentMessageID),
            now: 13)
        #expect(await store.list(owner: owner, archived: false, starred: nil).isEmpty)
        #expect(await store.list(owner: owner, archived: true, starred: false).isEmpty)
        let saved = try #require(await store.list(owner: owner, archived: true, starred: true).first)
        #expect(saved.title == "Renamed")
        #expect(saved.currentNodeID == request.parentMessageID)
        #expect(saved.updatedAt == 13)
        try await store.remove(id: turn.conversationID, owner: owner)
        await #expect(throws: ChatGPTHistoryError.notFound) {
            try await store.conversation(id: turn.conversationID, owner: owner)
        }
    }

    @Test("Encoded bound rejects admission and leaves no disk file")
    func encodedBound() async throws {
        let directory = historyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.json")
        let store = try ChatGPTHistoryStore(fileURL: file, limits: .init(storageBytes: 32))
        await #expect(throws: ChatGPTHistoryError.capacityExceeded) {
            try await store.begin(request: historyRequest(), owner: owner, now: 10)
        }
        #expect(await store.list(owner: owner, archived: false, starred: nil).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("Loaded version, owners, IDs and tree edges are validated")
    func loadedValidation() async throws {
        let directory = historyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.json")
        let store = try ChatGPTHistoryStore(fileURL: file)
        let turn = try await store.begin(request: historyRequest(), owner: owner, now: 10)
        let valid = try Data(contentsOf: file)
        var envelope = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        envelope["version"] = 2
        try JSONSerialization.data(withJSONObject: envelope).write(to: file)
        #expect(throws: ChatGPTHistoryError.unsupportedVersion) { try ChatGPTHistoryStore(fileURL: file) }
        envelope["version"] = 1
        let conversations = try #require(envelope["conversations"] as? [String: [String: Any]])
        let conversation = try #require(conversations[turn.conversationID])
        for (key, value) in [
            ("owner", "invalid"), ("id", UUID().uuidString), ("rootID", "invalid"),
            ("currentNodeID", UUID().uuidString),
        ] {
            var changed = conversation
            changed[key] = value
            envelope["conversations"] = [turn.conversationID: changed]
            let bytes = try JSONSerialization.data(withJSONObject: envelope)
            try bytes.write(to: file)
            #expect(throws: ChatGPTHistoryError.invalidStorage) { try ChatGPTHistoryStore(fileURL: file) }
            #expect(try Data(contentsOf: file) == bytes)
        }
        var changed = conversation
        var nodes = try #require(changed["nodes"] as? [String: [String: Any]])
        nodes[turn.assistantID]?["parentID"] = turn.assistantID
        changed["nodes"] = nodes
        envelope["conversations"] = [turn.conversationID: changed]
        try JSONSerialization.data(withJSONObject: envelope).write(to: file)
        #expect(throws: ChatGPTHistoryError.invalidStorage) { try ChatGPTHistoryStore(fileURL: file) }
    }
}
