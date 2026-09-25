import Foundation
import Hummingbird
import Logging
import NIOEmbedded
import Testing

@testable import LittleSwitchCore

@MainActor
struct ChatGPTExecutionBoundaryTests {
    @Test func staleFailureCannotReadOrOverwriteAReplacementTurn() async throws {
        let history = try ChatGPTHistoryStore()
        let owner = String(repeating: "a", count: 64)
        let pending = try await history.begin(request: historyRequest(), owner: owner, now: 1)
        let channel = ChatGPTStreamChannel()
        let projection = ChatGPTTurnProjection(
            pending: pending, model: "fixture", owner: owner, history: history, channel: channel)
        try await history.finish(
            conversationID: pending.conversationID,
            owner: owner,
            assistantID: pending.assistantID,
            status: .failed,
            now: 2)
        try await history.remove(id: pending.conversationID, owner: owner)
        let replacement = try await history.begin(
            request: historyRequest(text: "replacement private input"),
            owner: owner,
            now: 3,
            newConversationID: pending.conversationID)
        try await history.update(
            conversationID: replacement.conversationID,
            owner: owner,
            assistantID: replacement.assistantID,
            text: "replacement private output")
        let before = try await history.conversation(id: replacement.conversationID, owner: owner)
        let failure = Task { await projection.fail(cancelled: false) }
        let output: Data?
        do { output = try await channel.next() } catch {
            await channel.cancel()
            await failure.value
            throw error
        }
        await failure.value
        let bytes = try #require(output)
        let text = try #require(String(data: bytes, encoding: .utf8))
        #expect(text.contains(pending.assistantID))
        #expect(text.contains("[DONE]"))
        #expect(!text.contains("replacement private"))
        #expect(try await channel.next() == nil)
        #expect(try await history.conversation(id: replacement.conversationID, owner: owner) == before)
    }

    @Test func cancelledAdmissionCannotLeaveAProducerWaitingForReadiness() async throws {
        let fixture = chatGPTGatewayFixture()
        let history = try ChatGPTHistoryStore()
        let active = ChatGPTActiveTurns()
        let transport = RecordingGatewayTransport(responses: [])
        let responder = ChatGPTGatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            history: history,
            activeTurns: active)
        let channel = EmbeddedChannel()
        defer { _ = try? channel.finish() }
        let context = BasicRequestContext(source: .init(channel: channel, logger: Logger(label: #function)))
        let release = AsyncTestGate()
        let operation = Task {
            try? await release.wait()
            return try await responder.conversationResponse(
                historyRequest(),
                owner: String(repeating: "a", count: 64),
                history: history,
                context: context,
                capture: await fixture.state.routingCapture())
        }
        operation.cancel()
        await release.open()
        await #expect(throws: CancellationError.self) { try await operation.value }
        await active.shutdown()
        #expect(await transport.requests.isEmpty)
        let stored = await history.list(owner: String(repeating: "a", count: 64), archived: false, starred: nil)
        #expect(stored.allSatisfy { $0.nodes[$0.currentNodeID]?.status != .inProgress })
    }

    @Test func repeatedFailureDoesNotRewriteTheTerminalHistory() async throws {
        let history = try ChatGPTHistoryStore()
        let owner = String(repeating: "a", count: 64)
        let pending = try await history.begin(request: historyRequest(), owner: owner, now: 1)
        let channel = ChatGPTStreamChannel()
        let projection = ChatGPTTurnProjection(
            pending: pending, model: "fixture", owner: owner, history: history, channel: channel)
        await projection.fail(cancelled: true)
        let before = try await history.conversation(id: pending.conversationID, owner: owner)
        await projection.fail(cancelled: false)
        #expect(try await history.conversation(id: pending.conversationID, owner: owner) == before)
        #expect(before.nodes[pending.assistantID]?.status == .cancelled)
        await #expect(throws: ChatGPTStreamChannel.Failure.cancelled) { try await channel.next() }
    }
}
