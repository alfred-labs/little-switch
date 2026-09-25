import AsyncHTTPClient
import Foundation
import Hummingbird
import HummingbirdTesting
import LittleSwitchCommon
import NIOCore
import Testing

@testable import LittleSwitchCore

struct ChatGPTSelectedModelTests {
    @Test func queuedChatAdmissionIsRejectedWhenSelectionChangesWithoutConsumingCapacity() async throws {
        var snapshot = fixture().snapshot
        snapshot.providers[0].maximumParallelRequests = 1
        let provider = snapshot.providers[0]
        let state = GatewayState(snapshot: snapshot)
        let capture = await state.routingCapture()
        let occupiedID = UUID()
        try await state.admit(
            GatewayRequestAdmission(
                eventID: occupiedID,
                capture: capture,
                client: .codex,
                modelIdentifier: "example:codex-model",
                providerID: provider.id,
                targetModelID: "codex-model",
                retainedBodyBytes: 0))
        let waiter = Task { () throws -> GatewayAdmissionError? in
            do {
                try await state.admit(
                    GatewayRequestAdmission(
                        eventID: UUID(),
                        capture: capture,
                        client: .codex,
                        modelIdentifier: "example:chat-model",
                        providerID: provider.id,
                        targetModelID: "chat-model",
                        retainedBodyBytes: 0,
                        purpose: .chatGPTConversation))
                return nil
            } catch let error as GatewayAdmissionError {
                return error
            }
        }
        defer { waiter.cancel() }
        do {
            let _: Bool = try await eventually(description: "Chat admission waiting behind the Codex request") {
                await state.requestPoolSnapshot().totalWaiting == 1 ? true : nil
            }
            let changed = ChatGPTConfiguration(model: ModelMapping(providerID: provider.id, modelID: "codex-model"))
            _ = await state.replace(providers: [provider], mappings: [:], chatgpt: changed)
            let failure = try await valueWithinTimeout(waiter, description: "queued Chat route invalidation")
            #expect(failure == .invalidated)
            let occupied = await state.requestPoolSnapshot()
            #expect(occupied.totalRunning == 1)
            #expect(occupied.totalWaiting == 0)
            #expect(await state.sessionRequestCount == 1)
            await state.finish(eventID: occupiedID)
            let replacementID = UUID()
            let replacement = Task {
                try await state.admit(
                    GatewayRequestAdmission(
                        eventID: replacementID,
                        capture: await state.routingCapture(),
                        client: .codex,
                        modelIdentifier: "example:codex-model",
                        providerID: provider.id,
                        targetModelID: "codex-model",
                        retainedBodyBytes: 0,
                        purpose: .chatGPTConversation))
            }
            defer { replacement.cancel() }
            try await valueWithinTimeout(replacement, description: "replacement Chat admission after capacity release")
            #expect(await state.sessionRequestCount == 2)
            await state.finish(eventID: replacementID)
            let drained = await state.requestPoolSnapshot()
            #expect(drained.totalRunning == 0)
            #expect(drained.totalWaiting == 0)
        } catch {
            await state.stopAdmissions()
            await state.finish(eventID: occupiedID)
            throw error
        }
    }

    @Test func capturedChatAdmissionIsInvalidatedWhenSelectionChanges() async throws {
        let fixture = fixture()
        let capture = await fixture.state.routingCapture()
        let provider = fixture.snapshot.providers[0]
        let admission = GatewayRequestAdmission(
            eventID: UUID(),
            capture: capture,
            client: .codex,
            modelIdentifier: "example:chat-model",
            providerID: provider.id,
            targetModelID: "chat-model",
            retainedBodyBytes: 0,
            purpose: .chatGPTConversation)
        try await fixture.state.admit(admission)
        await fixture.state.finish(eventID: admission.eventID)
        let changed = ChatGPTConfiguration(model: ModelMapping(providerID: provider.id, modelID: "codex-model"))
        _ = await fixture.state.replace(providers: [provider], mappings: [:], chatgpt: changed)
        await #expect(throws: GatewayAdmissionError.invalidated) { try await fixture.state.admit(admission) }
        #expect(capture.snapshot.resolveChatGPT(model: "example:chat-model")?.model.id == "chat-model")
        #expect(capture.snapshot.resolveChatGPT(model: "example:codex-model") == nil)
        let preserved = await fixture.state.replace(providers: [provider], mappings: [:])
        #expect(preserved.chatgpt == changed)
    }

    @Test func selectedExcludedModelRoutesOnlyThroughChat() async throws {
        let fixture = fixture()
        let transport = RecordingGatewayTransport(responses: [try chatGPTProviderReply("Selected")])
        let application = Application(
            responder: ChatGPTGatewayResponder(
                state: fixture.state,
                transport: transport,
                secretStore: fixture.secrets,
                requiredAuthorityPort: nil,
                history: try ChatGPTHistoryStore()))
        try await application.test(.router) { client in
            let response = try await client.execute(
                uri: "/backend-api/f/conversation",
                method: .post,
                headers: chatGPTOwnerHeaders,
                body: ByteBuffer(bytes: chatGPTTurnBody(text: "Hello")))
            #expect(response.status == .ok)
            #expect(String(buffer: response.body).contains("Selected"))
        }
        #expect(await transport.requests.count == 1)
        let publicGateway = Application(
            responder: GatewayResponder(
                state: fixture.state, transport: transport, secretStore: fixture.secrets, requiredAuthorityPort: nil))
        try await publicGateway.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: #"{"model":"example:chat-model","input":"Hello"}"#))
            #expect(response.status == .badRequest)
        }
        #expect(await transport.requests.count == 1)
    }

    @Test(arguments: [false, true])
    func catalogContainsOnlySelectedModelAlongsideNative(deleted: Bool) async throws {
        let fixture = fixture(deleted: deleted)
        let transport = RecordingGatewayTransport(responses: [
            HTTPClientResponse(status: .ok, body: .bytes(ByteBuffer(string: #"{"models":[{"slug":"native"}]}"#)))
        ])
        try await chatGPTApplication(fixture: fixture, transport: transport).test(.router) { client in
            let response = try await client.execute(uri: "/backend-api/models", method: .get)
            let object = try chatJSONObject(Data(response.body.readableBytesView))
            let models = try #require(object["models"] as? [[String: Any]])
            #expect(
                models.compactMap { $0["slug"] as? String }
                    == (deleted ? ["native"] : ["native", "example:chat-model"]))
        }
    }

    private func fixture(deleted: Bool = false) -> GatewayFixture {
        var provider = chatGPTGatewayFixture().snapshot.providers[0]
        provider.responsesWireOverride = .native
        provider.models = deleted ? [] : [DiscoveredModel(id: "chat-model")]
        provider.models.append(DiscoveredModel(id: "codex-model"))
        let selection = ModelMapping(providerID: provider.id, modelID: "chat-model")
        let snapshot = RoutingSnapshot(
            generation: 1,
            providers: [provider],
            mappings: [:],
            codex: CodexConfiguration(
                defaultModel: ModelMapping(providerID: provider.id, modelID: "codex-model"), excludedModels: [selection]
            ),
            chatgpt: ChatGPTConfiguration(connected: true, model: selection))
        return GatewayFixture(snapshot: snapshot, state: GatewayState(snapshot: snapshot), secrets: MemorySecretStore())
    }
}
