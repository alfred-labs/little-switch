import Testing

@testable import LittleSwitchCore

struct ChatGPTActiveTurnsTests {
    @Test func stopCancelsOnlyTheMatchingAccountConversation() async throws {
        let turns = ChatGPTActiveTurns()
        let key = ChatGPTActiveTurns.Key(owner: "one", conversationID: "same")
        let wrong = ChatGPTActiveTurns.Key(owner: "two", conversationID: "same")
        let started = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let result = ChatGPTCancellationResult()
        let task = try await turns.start(key: key) {
            started.continuation.yield()
            for await _ in release.stream { break }
            await result.record(Task.isCancelled)
        }
        for await _ in started.stream { break }
        await turns.cancel(key: wrong)
        #expect(!task.isCancelled)
        await turns.cancel(key: key)
        release.continuation.finish()
        await task.value
        #expect(await result.cancelled == true)
        await turns.shutdown()
    }

    @Test func rejectsDuplicateTurnsAndCapacityWithoutReplacingTasks() async throws {
        let turns = ChatGPTActiveTurns(maximumActive: 1)
        let key = ChatGPTActiveTurns.Key(owner: "one", conversationID: "first")
        let release = AsyncStream<Void>.makeStream()
        let task = try await turns.start(key: key) { for await _ in release.stream { break } }
        await #expect(throws: ChatGPTActiveTurns.Failure.busy) {
            try await turns.start(key: key) {}
        }
        await #expect(throws: ChatGPTActiveTurns.Failure.capacity) {
            try await turns.start(key: .init(owner: "one", conversationID: "second")) {}
        }
        release.continuation.finish()
        await task.value
        await turns.shutdown()
        await #expect(throws: ChatGPTActiveTurns.Failure.stopped) {
            try await turns.start(key: key) {}
        }
    }
}

private actor ChatGPTCancellationResult {
    private(set) var cancelled: Bool?
    func record(_ value: Bool) { cancelled = value }
}
