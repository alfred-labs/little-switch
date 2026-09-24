import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import LittleSwitchCommon
import Logging
import NIOCore
import NIOEmbedded
import Testing

@testable import LittleSwitchCore

struct ChatGPTResponseLifetimeTests {
    @Test func droppingAnUnwrittenResponseCancelsItsReservedTurn() async throws {
        let fixture = try ChatGPTResponseLifetimeFixture()
        var response: Response? = try await fixture.response()
        #expect(response?.status == .ok)
        let stored = try #require(await fixture.history.list(owner: fixture.owner, archived: false, starred: nil).first)
        #expect(stored.nodes[stored.currentNodeID]?.status == .inProgress)
        #expect(await fixture.transport.requests.isEmpty)

        response = nil
        let cancelled: ChatGPTStoredConversation = try await eventually(description: "discarded turn cancellation") {
            let value = try await fixture.history.conversation(id: stored.id, owner: fixture.owner)
            return value.nodes[value.currentNodeID]?.status == .cancelled ? value : nil
        }
        #expect(cancelled.nodes[cancelled.currentNodeID]?.text.isEmpty == true)
        #expect(await fixture.transport.requests.isEmpty)
        await fixture.active.shutdown()
        try await fixture.state.admit(client: .codex)
    }

    @Test func stoppingTheListenerReleasesAProducerBlockedOnItsConsumer() async throws {
        let fixture = try ChatGPTResponseLifetimeFixture()
        let issued = try GatewayTLSIdentityFactory.make()
        let identity = try GatewayTLSIdentity(
            certificatePEM: issued.certificatePEM,
            authorityPEM: issued.authorityPEM,
            keyPEM: issued.keyPEM
        )
        let server = ChatGPTGatewayServer(
            state: fixture.state,
            secretStore: MemorySecretStore(),
            tlsIdentity: identity,
            transport: fixture.transport,
            history: fixture.history,
            activeTurns: fixture.active,
            listenPort: 0
        )
        try await server.start()
        let writer = ChatGPTBlockedResponseWriter()
        var consumer: Task<Bool, Never>?
        do {
            let response = try await fixture.response()
            let reading = Task {
                do {
                    try await response.body.write(writer)
                    return false
                } catch { return true }
            }
            consumer = reading
            try await writer.entered.wait(description: "the initial Chat snapshot")
            // The producer has persisted a partial delta and is now waiting for
            // the consumer, which still holds the preceding initial snapshot.
            let pending: ChatGPTStoredConversation = try await eventually(description: "a backpressured Chat delta") {
                let value = await fixture.history.list(owner: fixture.owner, archived: false, starred: nil).first
                return value?.nodes[value?.currentNodeID ?? ""]?.text == "Partial" ? value : nil
            }
            #expect(pending.nodes[pending.currentNodeID]?.status == .inProgress)
            let stopping = Task { await server.stop() }
            try await stopWithConsumerWatchdog(stopping, release: writer.release)
            await writer.release.open()
            #expect(try await valueWithinTimeout(reading, description: "the cancelled consumer"))
            let final = try await fixture.history.conversation(id: pending.id, owner: fixture.owner)
            #expect(final.nodes[final.currentNodeID]?.status == .cancelled)
            #expect(final.nodes[final.currentNodeID]?.text == "Partial")
            #expect(await !server.isRunning)
            #expect(await fixture.state.requestPoolSnapshot().totalRunning == 0)
            try await fixture.state.admit(client: .codex)
        } catch {
            consumer?.cancel()
            await writer.release.open()
            await server.stop()
            if let consumer { _ = await consumer.value }
            throw error
        }
    }

    @Test func shutdownWatchdogReleasesAStalledConsumerAndReportsTimeout() async {
        let release = AsyncTestGate()
        let consumer = Task { try? await release.wait() }
        // Cancelling shutdown cannot unblock its separately owned consumer.
        let stopping = Task { _ = await consumer.value }

        await #expect(throws: AsyncTestTimeout(operation: "listener shutdown with a blocked consumer")) {
            try await stopWithConsumerWatchdog(stopping, release: release, timeout: .zero)
        }
        await stopping.value
        _ = await consumer.value
    }
}

private func stopWithConsumerWatchdog(
    _ stopping: Task<Void, Never>,
    release: AsyncTestGate,
    timeout: Duration = .seconds(5)
) async throws {
    // This task must release the consumer independently of awaiting shutdown:
    // a structured timeout race would itself wait for the stalled stop task.
    let watchdog = Task {
        do {
            try await Task.sleep(for: timeout)
        } catch {
            return false
        }
        await release.open()
        return true
    }
    await stopping.value
    watchdog.cancel()
    if await watchdog.value {
        throw AsyncTestTimeout(operation: "listener shutdown with a blocked consumer")
    }
}

private struct ChatGPTResponseLifetimeFixture: Sendable {
    let state: GatewayState
    let history: ChatGPTHistoryStore
    let transport: RecordingGatewayTransport
    let active = ChatGPTActiveTurns()
    let owner: String

    init() throws {
        var provider = chatGPTGatewayFixture().snapshot.providers[0]
        provider.responsesWireOverride = .native
        state = GatewayState(snapshot: .init(generation: 1, providers: [provider], mappings: [:]))
        history = try ChatGPTHistoryStore()
        owner = try ChatGPTRequestBoundary.accountPartition(headers: chatGPTOwnerHeaders)
        transport = RecordingGatewayTransport(responses: [
            HTTPClientResponse(
                status: .ok,
                headers: ["content-type": "text/event-stream"],
                body: .bytes(
                    ByteBuffer(string: "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Partial\"}\n\n"))
            )
        ])
    }

    func response() async throws -> Response {
        let responder = ChatGPTGatewayResponder(
            state: state,
            transport: transport,
            secretStore: MemorySecretStore(),
            requiredAuthorityPort: nil,
            history: history,
            activeTurns: active
        )
        let request = Request(
            head: HTTPRequest(
                method: .post,
                scheme: "https",
                authority: "localhost",
                path: "/backend-api/f/conversation",
                headerFields: chatGPTOwnerHeaders
            ),
            body: RequestBody(buffer: ByteBuffer(bytes: try chatGPTTurnBody(text: "Synthetic cancellation")))
        )
        let context = BasicRequestContext(
            source: .init(channel: EmbeddedChannel(), logger: Logger(label: #function))
        )
        return try await responder.respond(to: request, context: context)
    }
}

private struct ChatGPTBlockedResponseWriter: ResponseBodyWriter {
    let entered = AsyncTestGate()
    let release = AsyncTestGate()

    mutating func write(_ buffer: ByteBuffer) async throws {
        _ = buffer
        await entered.open()
        try await release.wait()
    }

    consuming func finish(_ trailingHeaders: HTTPFields?) async throws {
        _ = trailingHeaders
    }
}
