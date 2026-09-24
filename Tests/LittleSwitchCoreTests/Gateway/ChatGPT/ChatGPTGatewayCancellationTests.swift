import AsyncHTTPClient
import Foundation
import Hummingbird
import HummingbirdTesting
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

struct ChatGPTGatewayCancellationTests {
    @Test(arguments: [false, true])
    func stopCancelsTheOwnedTurnWhileQueuedOrExecuting(queued: Bool) async throws {
        var provider = chatGPTGatewayFixture().snapshot.providers[0]
        provider.responsesWireOverride = .native
        provider.maximumParallelRequests = 1
        let state = GatewayState(snapshot: .init(generation: 1, providers: [provider], mappings: [:]))
        let history = try ChatGPTHistoryStore()
        let owner = try ChatGPTRequestBoundary.accountPartition(headers: chatGPTOwnerHeaders)
        let transport = ChatGPTWaitingTransport()
        let active = ChatGPTActiveTurns()
        let occupiedID = UUID()
        if queued {
            try await state.admit(
                .init(
                    eventID: occupiedID,
                    capture: state.routingCapture(),
                    client: .codex,
                    modelIdentifier: "example:chat-model",
                    providerID: provider.id,
                    targetModelID: "chat-model",
                    retainedBodyBytes: 1
                )
            )
        }
        let application = Application(
            responder: ChatGPTGatewayResponder(
                state: state,
                transport: transport,
                secretStore: MemorySecretStore(),
                requiredAuthorityPort: nil,
                history: history,
                activeTurns: active
            )
        )
        do {
            try await application.test(.router) { client in
                let running = Task {
                    do {
                        _ = try await client.execute(
                            uri: "/backend-api/f/conversation",
                            method: .post,
                            headers: chatGPTOwnerHeaders,
                            body: ByteBuffer(bytes: chatGPTTurnBody(text: "A cancellable turn"))
                        )
                        return false
                    } catch { return true }
                }
                defer { running.cancel() }
                let stored: ChatGPTStoredConversation = try await eventually(description: "a local conversation") {
                    await history.list(owner: owner, archived: false, starred: nil).first
                }
                if queued {
                    let _: Bool = try await eventually(description: "the Chat turn to enter the shared queue") {
                        await state.requestPoolSnapshot().totalWaiting == 1 ? true : nil
                    }
                } else {
                    try await transport.entered.wait(description: "the provider request")
                }
                let stopBody = ByteBuffer(bytes: try JSONEncoder().encode(["conversation_id": stored.id]))
                let foreign = try await client.execute(
                    uri: "/backend-api/stop_conversation",
                    method: .post,
                    headers: [.authorization: "Bearer another-synthetic-account"],
                    body: stopBody
                )
                #expect(foreign.status == .notFound)
                let stop = try await client.execute(
                    uri: "/backend-api/stop_conversation",
                    method: .post,
                    headers: chatGPTOwnerHeaders,
                    body: stopBody
                )
                #expect(stop.status == .ok)
                #expect(try await valueWithinTimeout(running, description: "the cancelled response to close"))
                let final = try await history.conversation(id: stored.id, owner: owner)
                #expect(final.nodes[final.currentNodeID]?.status == .cancelled)
                #expect(await state.requestPoolSnapshot().totalWaiting == 0)
                #expect(await transport.count == (queued ? 0 : 1))
            }
        } catch {
            await active.shutdown()
            await state.finish(eventID: occupiedID)
            throw error
        }
        await active.shutdown()
        await state.finish(eventID: occupiedID)
        try await state.admit(client: .codex)
    }
}

private actor ChatGPTWaitingTransport: UpstreamTransport {
    let entered = AsyncTestGate()
    private let release = AsyncTestGate()
    private(set) var count = 0

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        _ = request
        count += 1
        await entered.open()
        try await release.wait()
        throw CancellationError()
    }
}
