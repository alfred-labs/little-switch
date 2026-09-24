import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import LittleSwitchTransport
import Logging
import NIOCore
import NIOEmbedded
import Testing

@testable import LittleSwitchCore

@MainActor
struct ChatGPTGatewayFailureBoundaryTests {
    @Test(arguments: [false, true])
    func requestBodyFailureNeverReachesUpstream(cancelled: Bool) async throws {
        let fixture = chatGPTGatewayFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let responder = ChatGPTGatewayResponder(
            state: fixture.state, transport: transport, secretStore: fixture.secrets, requiredAuthorityPort: nil)
        let request = Request(
            head: HTTPRequest(
                method: .post, scheme: "https", authority: "localhost", path: "/backend-api/conversation"),
            body: cancelled
                ? RequestBody(asyncSequence: CancellingGatewayBodySequence())
                : RequestBody(asyncSequence: FailingGatewayBodySequence()))
        let channel = EmbeddedChannel()
        defer { _ = try? channel.finish() }
        let context = BasicRequestContext(source: .init(channel: channel, logger: Logger(label: #function)))
        if cancelled {
            await #expect(throws: CancellationError.self) { try await responder.respond(to: request, context: context) }
        } else {
            #expect(try await responder.respond(to: request, context: context).status == .contentTooLarge)
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test(arguments: [false, true])
    func upstreamCancellationPropagatesForNativeAndMergedHistory(historyList: Bool) async throws {
        let history = try ChatGPTHistoryStore()
        let owner = try ChatGPTRequestBoundary.accountPartition(headers: chatGPTOwnerHeaders)
        _ = try await history.begin(request: historyRequest(), owner: owner, now: 1)
        let fixture = chatGPTGatewayFixture()
        let responder = ChatGPTGatewayResponder(
            state: fixture.state,
            transport: ChatGPTCancellingTransport(),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            history: history)
        let channel = EmbeddedChannel()
        defer { _ = try? channel.finish() }
        let context = BasicRequestContext(source: .init(channel: channel, logger: Logger(label: #function)))
        let request = Request(
            head: HTTPRequest(
                method: .get,
                scheme: "https",
                authority: "localhost",
                path: historyList ? "/backend-api/conversations" : "/backend-api/models",
                headerFields: chatGPTOwnerHeaders),
            body: RequestBody(buffer: ByteBuffer()))
        await #expect(throws: CancellationError.self) {
            try await responder.respond(to: request, context: context)
        }
    }

    @Test(arguments: [false, true], [false, true])
    func redirectsAreRejectedAndOtherNativeErrorsPreserved(historyList: Bool, redirect: Bool) async throws {
        let history = try ChatGPTHistoryStore()
        let owner = try ChatGPTRequestBoundary.accountPartition(headers: chatGPTOwnerHeaders)
        _ = try await history.begin(request: historyRequest(), owner: owner, now: 1)
        let transport = RecordingGatewayTransport(responses: [
            HTTPClientResponse(
                status: redirect ? .found : .forbidden, body: .bytes(ByteBuffer(string: "native denial")))
        ])
        try await managedChatGPTApplication(transport: transport, history: history).test(.router) { client in
            let response = try await client.execute(
                uri: historyList ? "/backend-api/conversations" : "/backend-api/models",
                method: .get,
                headers: chatGPTOwnerHeaders)
            #expect(response.status == (redirect ? .badGateway : .forbidden))
            if !redirect { #expect(String(buffer: response.body) == "native denial") }
        }
    }

    @Test func malformedNativeCatalogFailsWithoutPublishingLocalModels() async throws {
        let transport = RecordingGatewayTransport(responses: [
            HTTPClientResponse(status: .ok, body: .bytes(ByteBuffer(string: "invalid catalog")))
        ])
        try await chatGPTApplication(fixture: chatGPTGatewayFixture(), transport: transport).test(.router) { client in
            let response = try await client.execute(uri: "/backend-api/models", method: .get)
            #expect(response.status == .badGateway)
            #expect(!String(buffer: response.body).contains("example:chat-model"))
        }
    }

    @Test func historyAdmissionFailureReturnsBeforeStartingProvider() async throws {
        let history = try ChatGPTHistoryStore(limits: .init(conversations: 1))
        let owner = try ChatGPTRequestBoundary.accountPartition(headers: chatGPTOwnerHeaders)
        _ = try await history.begin(request: historyRequest(), owner: owner, now: 1)
        let transport = RecordingGatewayTransport(responses: [])
        try await managedChatGPTApplication(transport: transport, history: history).test(.router) { client in
            let response = try await client.execute(
                uri: "/backend-api/f/conversation",
                method: .post,
                headers: chatGPTOwnerHeaders,
                body: ByteBuffer(bytes: chatGPTTurnBody(text: "At capacity")))
            #expect(response.status == .contentTooLarge)
        }
        #expect(await transport.requests.isEmpty)
    }
}

private struct ChatGPTCancellingTransport: UpstreamTransport {
    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse { throw CancellationError() }
}
