import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("ChatGPT history persistence")
struct ChatGPTHistoryPersistenceTests {
    let owner = String(repeating: "a", count: 64)

    @Test func failedAtomicReplacementPreservesTheExistingDirectory() throws {
        let directory = historyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appending(path: "history.json")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let sentinel = destination.appending(path: "keep")
        try Data("original".utf8).write(to: sentinel)
        #expect(throws: ChatGPTHistoryError.persistenceFailed) {
            try ChatGPTHistoryPersistence.save([:], fileURL: destination, limits: .init())
        }
        #expect(try Data(contentsOf: sentinel) == Data("original".utf8))
    }

    @Test func validVersionWithInvalidEnvelopeIsNotAnEmptyHistory() throws {
        let directory = historyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "history.json")
        let bytes = Data(#"{"version":1,"conversations":[]}"#.utf8)
        try bytes.write(to: file)
        #expect(throws: ChatGPTHistoryError.invalidStorage) { try ChatGPTHistoryStore(fileURL: file) }
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test func directoriesAreNotAcceptedAsHistoryFiles() throws {
        let directory = historyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #expect(throws: ChatGPTHistoryError.invalidStorage) { try ChatGPTHistoryStore(fileURL: directory) }
    }

    @Test func inaccessibleParentReportsPersistenceFailure() throws {
        let directory = historyDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: directory.path)
        #expect(throws: ChatGPTHistoryError.persistenceFailed) {
            try ChatGPTHistoryStore(fileURL: directory.appending(path: "nested/history.json"))
        }
    }

    @Test func unreadableHistoryIsNotTreatedAsMissing() throws {
        let directory = historyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "history.json")
        try Data(#"{"version":1,"conversations":{}}"#.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        #expect(throws: ChatGPTHistoryError.persistenceFailed) { try ChatGPTHistoryStore(fileURL: file) }
    }

    @Test("Restart restores tree, native timestamps, and cancels unfinished assistants")
    func restart() async throws {
        let directory = historyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.json")
        let store = try ChatGPTHistoryStore(fileURL: file)
        let request = historyRequest()
        let turn = try await store.begin(request: request, owner: owner, now: 10)
        let initialBytes = try Data(contentsOf: file)
        try await store.update(
            conversationID: turn.conversationID, owner: owner, assistantID: turn.assistantID, text: "partial")
        #expect(try Data(contentsOf: file) == initialBytes)
        let restored = try ChatGPTHistoryStore(fileURL: file)
        let recovered = try await restored.conversation(id: turn.conversationID, owner: owner)
        #expect(recovered.nodes[turn.assistantID]?.status == .cancelled)
        let detail = try #require(JSONSerialization.jsonObject(with: recovered.nativeData()) as? [String: Any])
        #expect(detail["owner"] == nil)
        #expect(detail["current_node"] as? String == turn.assistantID)
        let mapping = try #require(detail["mapping"] as? [String: [String: Any]])
        #expect(mapping.count == 3)
        #expect(mapping[request.parentMessageID]?["message"] is NSNull)
        #expect(mapping[request.parentMessageID]?["children"] as? [String] == [request.messages[0].id])
        let summary = try #require(JSONSerialization.jsonObject(with: recovered.summaryData()) as? [String: Any])
        #expect(summary["create_time"] as? String == "1970-01-01T00:00:10Z")
        #expect(try historyPermissions(directory) == 0o700)
        #expect(try historyPermissions(file) == 0o600)
        try await store.finish(
            conversationID: turn.conversationID,
            owner: owner,
            assistantID: turn.assistantID,
            status: .cancelled,
            now: 12)
        let finalStore = try ChatGPTHistoryStore(fileURL: file)
        let final = try await finalStore.conversation(id: turn.conversationID, owner: owner)
        #expect(final.nodes[turn.assistantID]?.text == "partial")
        #expect(final.nodes[turn.assistantID]?.updatedAt == 12)
    }

    @Test("Temporary conversations are bounded but never listed or written")
    func temporary() async throws {
        let directory = historyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.json")
        let store = try ChatGPTHistoryStore(fileURL: file, limits: .init(conversations: 1))
        let turn = try await store.begin(request: historyRequest(temporary: true), owner: owner, now: 10)
        #expect(await store.list(owner: owner, archived: false, starred: nil).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        await #expect(throws: ChatGPTHistoryError.capacityExceeded) {
            try await store.begin(request: historyRequest(temporary: true), owner: owner, now: 11)
        }
        try await store.finish(
            conversationID: turn.conversationID,
            owner: owner,
            assistantID: turn.assistantID,
            status: .cancelled,
            now: 12)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test(
        "Persistence failure rolls back admission and patch; finishing releases active turn",
        arguments: [ChatGPTNativeMessage.Status.cancelled, .failed, .finishedSuccessfully])
    func rollback(status: ChatGPTNativeMessage.Status) async throws {
        let directory = historyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = directory.appending(path: "blocker")
        try Data().write(to: blocker)
        let store = try ChatGPTHistoryStore(fileURL: blocker.appending(path: "nested/history.json"))
        await #expect(throws: ChatGPTHistoryError.persistenceFailed) {
            try await store.begin(request: historyRequest(), owner: owner, now: 10)
        }
        #expect(await store.list(owner: owner, archived: false, starred: nil).isEmpty)
        let file = directory.appending(path: "real/history.json")
        let working = try ChatGPTHistoryStore(fileURL: file)
        let turn = try await working.begin(request: historyRequest(), owner: owner, now: 10)
        try await working.update(
            conversationID: turn.conversationID, owner: owner, assistantID: turn.assistantID, text: "partial answer")
        try FileManager.default.removeItem(at: file.deletingLastPathComponent())
        try Data().write(to: file.deletingLastPathComponent())
        await #expect(throws: ChatGPTHistoryError.persistenceFailed) {
            try await working.finish(
                conversationID: turn.conversationID,
                owner: owner,
                assistantID: turn.assistantID,
                status: status,
                now: 11)
        }
        let expectedStatus: ChatGPTNativeMessage.Status = status == .cancelled ? .cancelled : .failed
        let beforePatch = try await working.conversation(id: turn.conversationID, owner: owner)
        #expect(beforePatch.nodes[turn.assistantID]?.status == expectedStatus)
        #expect(beforePatch.nodes[turn.assistantID]?.text == "partial answer")
        let detail = try #require(JSONSerialization.jsonObject(with: beforePatch.nativeData()) as? [String: Any])
        let mapping = try #require(detail["mapping"] as? [String: [String: Any]])
        let message = try #require(mapping[turn.assistantID]?["message"] as? [String: Any])
        #expect(message["status"] as? String == expectedStatus.rawValue)
        let metadata = try #require(message["metadata"] as? [String: Any])
        #expect(metadata["finish_details"] == nil)
        await #expect(throws: ChatGPTHistoryError.persistenceFailed) {
            try await working.patch(id: turn.conversationID, owner: owner, changes: .init(title: "unsaved"), now: 12)
        }
        #expect(try await working.conversation(id: turn.conversationID, owner: owner) == beforePatch)
        try FileManager.default.removeItem(at: file.deletingLastPathComponent())
        try await working.patch(id: turn.conversationID, owner: owner, changes: .init(title: "saved"), now: 12)
        let value = try await working.conversation(id: turn.conversationID, owner: owner)
        #expect(value.title == "saved")
        #expect(value.nodes[turn.assistantID]?.status == expectedStatus)
        let restored = try ChatGPTHistoryStore(fileURL: file)
        #expect(try await restored.conversation(id: turn.conversationID, owner: owner) == value)
    }

    @Test("Corrupt and oversized files are rejected without overwriting")
    func corrupt() throws {
        let directory = historyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "history.json")
        let bytes = Data("broken".utf8)
        try bytes.write(to: file)
        #expect(throws: ChatGPTHistoryError.invalidStorage) { try ChatGPTHistoryStore(fileURL: file) }
        #expect(throws: ChatGPTHistoryError.capacityExceeded) {
            try ChatGPTHistoryStore(fileURL: file, limits: .init(storageBytes: 1))
        }
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test("Final directory and file symlinks are rejected")
    func symlinks() throws {
        let directory = historyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let link = directory.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)
        #expect(throws: ChatGPTHistoryError.unsafeStorage) {
            try ChatGPTHistoryStore(fileURL: link.appending(path: "history.json"))
        }
        let file = directory.appending(path: "history.json")
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: directory.appending(path: "missing"))
        #expect(throws: ChatGPTHistoryError.unsafeStorage) { try ChatGPTHistoryStore(fileURL: file) }
    }
}

func historyDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "chat-history-\(UUID().uuidString)")
}

func historyPermissions(_ url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try #require((attributes[.posixPermissions] as? NSNumber)?.intValue)
}
