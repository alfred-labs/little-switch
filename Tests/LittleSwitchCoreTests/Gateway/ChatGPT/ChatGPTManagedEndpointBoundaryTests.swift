import AsyncHTTPClient
import Foundation
import HTTPTypes
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

struct ChatGPTManagedEndpointBoundaryTests {
    @Test func initializationInfersStoredModelAndOmitsItForAUserNode() async throws {
        let history = try ChatGPTHistoryStore()
        let owner = try ChatGPTRequestBoundary.accountPartition(headers: chatGPTOwnerHeaders)
        let request = historyRequest()
        let turn = try await history.begin(request: request, owner: owner, now: 1)
        try await history.finish(
            conversationID: turn.conversationID,
            owner: owner,
            assistantID: turn.assistantID,
            status: .finishedSuccessfully,
            now: 2)
        let transport = RecordingGatewayTransport(responses: [])
        try await managedChatGPTApplication(transport: transport, history: history).test(.router) { client in
            for node in [turn.assistantID, request.messages[0].id] {
                try await history.patch(
                    id: turn.conversationID,
                    owner: owner,
                    changes: .init(currentNodeID: node),
                    now: 3)
                let response = try await client.execute(
                    uri: "/backend-api/conversation/init",
                    method: .post,
                    headers: chatGPTOwnerHeaders,
                    body: ByteBuffer(bytes: JSONEncoder().encode(["conversation_id": turn.conversationID])))
                #expect(response.status == .ok)
                let metadata = try JSONDecoder().decode(
                    [String: String].self, from: Data(response.body.readableBytesView))
                var expected = ["type": "conversation_detail_metadata", "conversation_id": turn.conversationID]
                if node == turn.assistantID { expected["default_model_slug"] = "fixture" }
                #expect(metadata == expected)
            }
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test func statusTracksPersistedTurnAndPatchChangesTheOwnedTree() async throws {
        let history = try ChatGPTHistoryStore()
        let owner = try ChatGPTRequestBoundary.accountPartition(headers: chatGPTOwnerHeaders)
        let request = historyRequest()
        let pending = try await history.begin(request: request, owner: owner, now: 1)
        let transport = RecordingGatewayTransport(responses: [])
        try await managedChatGPTApplication(transport: transport, history: history).test(.router) { client in
            let path = "/backend-api/conversation/" + pending.conversationID
            for (status, expected) in [
                (ChatGPTNativeMessage.Status.inProgress, "IS_STREAMING"),
                (.finishedSuccessfully, "COMPLETE"), (.failed, "FAILURE"),
            ] {
                if status != .inProgress {
                    if status == .failed {
                        try await history.patch(
                            id: pending.conversationID,
                            owner: owner,
                            changes: .init(currentNodeID: request.parentMessageID),
                            now: 3)
                    } else {
                        try await history.finish(
                            conversationID: pending.conversationID,
                            owner: owner,
                            assistantID: pending.assistantID,
                            status: status,
                            now: 2)
                    }
                }
                let response = try await client.execute(
                    uri: path + "/stream_status", method: .get, headers: chatGPTOwnerHeaders)
                #expect(response.status == .ok)
                let object = try chatJSONObject(Data(response.body.readableBytesView))
                #expect(object["status"] as? String == expected)
                #expect(object["conversation_id"] as? String == pending.conversationID)
            }
            let patch = try await client.execute(
                uri: path,
                method: .patch,
                headers: chatGPTOwnerHeaders,
                body: ByteBuffer(string: #"{"title":"Renamed","is_archived":true,"is_starred":true,"is_visible":true}"#)
            )
            #expect(patch.status == .ok)
            let stored = try await history.conversation(id: pending.conversationID, owner: owner)
            #expect(stored.title == "Renamed")
            #expect(stored.archived && stored.starred)
            let removed = try await client.execute(
                uri: path,
                method: .patch,
                headers: chatGPTOwnerHeaders,
                body: ByteBuffer(string: #"{"is_visible":false}"#))
            #expect(removed.status == .ok)
            #expect(try await client.execute(uri: path, method: .get, headers: chatGPTOwnerHeaders).status == .notFound)
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test func missingSessionAndBusyHistoryRemainLocal() async throws {
        let history = try ChatGPTHistoryStore()
        let owner = try ChatGPTRequestBoundary.accountPartition(headers: chatGPTOwnerHeaders)
        let pending = try await history.begin(request: historyRequest(), owner: owner, now: 1)
        let transport = RecordingGatewayTransport(responses: [])
        try await managedChatGPTApplication(transport: transport, history: history).test(.router) { client in
            let path = "/backend-api/conversation/" + pending.conversationID
            let unauthorized = try await client.execute(uri: path, method: .get)
            let busy = try await client.execute(uri: path, method: .delete, headers: chatGPTOwnerHeaders)
            #expect(unauthorized.status == .unauthorized)
            #expect(busy.status == .conflict)
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test func errorMappingDoesNotExposeUnderlyingStorageOrTransportDetails() async throws {
        let fixture = chatGPTGatewayFixture()
        let responder = ChatGPTGatewayResponder(
            state: fixture.state, transport: RecordingGatewayTransport(responses: []), secretStore: fixture.secrets)
        let cases: [(any Error, HTTPResponse.Status)] = [
            (ChatGPTHistoryError.capacityExceeded, .contentTooLarge),
            (ChatGPTActiveTurns.Failure.capacity, .tooManyRequests),
            (ChatGPTActiveTurns.Failure.stopped, .serviceUnavailable),
            (ChatGPTHistoryError.persistenceFailed, .internalServerError),
            (
                NSError(
                    domain: "private-storage-path", code: 1, userInfo: [NSLocalizedDescriptionKey: "private-detail"]),
                .internalServerError
            ),
        ]
        for (error, status) in cases {
            let response = try responder.managedErrorResponse(error)
            #expect(response.status == status)
            #expect(response.headers[.cacheControl] == "no-store")
            let data = try await responseBodyData(response.body)
            let object = try JSONDecoder().decode([String: String].self, from: data)
            #expect(object.count == 1)
            #expect(object["detail"]?.isEmpty == false)
            let text = try #require(String(data: data, encoding: .utf8))
            #expect(!text.contains("private-"))
        }
    }
}
