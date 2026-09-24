import AsyncHTTPClient
import Foundation
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

struct ChatGPTGatewayHistoryListTests {
    @Test func mergedHistoryPreservesCookieDeletionAndDropsStaleRepresentationHeaders() async throws {
        let history = try ChatGPTHistoryStore()
        let owner = try ChatGPTRequestBoundary.accountPartition(headers: chatGPTOwnerHeaders)
        let pending = try await history.begin(
            request: ChatGPTConversationRequest.decode(chatGPTTurnBody(text: "Local")), owner: owner, now: 1)
        let transport = RecordingGatewayTransport(responses: [
            HTTPClientResponse(
                status: .ok,
                headers: [
                    "set-cookie": "session=; Domain=.chatgpt.com; Max-Age=0; Path=/; Secure; HttpOnly",
                    "etag": "native", "last-modified": "Thu, 24 Sep 2026 00:00:00 GMT",
                    "content-encoding": "identity", "cache-control": "max-age=3600",
                ],
                body: .bytes(ByteBuffer(string: #"{"items":[],"total":0}"#))
            )
        ])
        try await managedChatGPTApplication(transport: transport, history: history).test(.router) { client in
            let response = try await client.execute(
                uri: "/backend-api/conversations", method: .get, headers: chatGPTOwnerHeaders)
            #expect(response.status == .ok)
            #expect(response.headers[values: .setCookie] == ["session=; Max-Age=0; Path=/; Secure; HttpOnly"])
            #expect(response.headers[.eTag] == nil)
            #expect(response.headers[.lastModified] == nil)
            #expect(response.headers[.contentEncoding] == nil)
            #expect(response.headers[.contentType] == "application/json")
            #expect(response.headers[.cacheControl] == "no-store")
            let merged = try chatJSONObject(Data(response.body.readableBytesView))
            #expect(
                (merged["items"] as? [[String: Any]])?.compactMap { $0["id"] as? String } == [pending.conversationID])
        }
    }

    @Test func defaultPaginationAndExplicitOriginPreserveNativePagination() throws {
        let page = try ChatGPTHistoryList(
            url: "https://chatgpt.com/backend-api/conversations?conversation_origin=chatgpt")
        #expect(page.includesLocal)
        #expect(
            try page.nativeURL(localCount: 2)
                == "https://chatgpt.com/backend-api/conversations?conversation_origin=chatgpt&offset=0&limit=18")
        let merged = try page.merge(nativeData: Data(#"{"items":[],"total":21,"has_more":false}"#.utf8), local: [])
        #expect(try chatJSONObject(merged)["has_more"] as? Bool == true)
        let last = try ChatGPTHistoryList(url: "https://chatgpt.com/backend-api/conversations?offset=20")
        #expect(try chatJSONObject(last.merge(nativeData: merged, local: []))["has_more"] as? Bool == false)
    }
    @Test func localPrefixPaginationKeepsEveryNativeItemAndTotal() async throws {
        let history = try ChatGPTHistoryStore()
        let owner = try ChatGPTRequestBoundary.accountPartition(headers: chatGPTOwnerHeaders)
        let pending = try await history.begin(
            request: ChatGPTConversationRequest.decode(chatGPTTurnBody(text: "Local")),
            owner: owner,
            now: 100
        )
        try await history.finish(
            conversationID: pending.conversationID,
            owner: owner,
            assistantID: pending.assistantID,
            status: .finishedSuccessfully,
            now: 101
        )
        let transport = RecordingGatewayTransport(responses: [
            HTTPClientResponse(
                status: .ok,
                body: .bytes(
                    ByteBuffer(
                        string:
                            #"{"items":[{"id":"native-first"}],"total":2,"limit":1,"offset":0,"has_missing_conversations":false}"#
                    )
                )
            ),
            HTTPClientResponse(
                status: .ok,
                body: .bytes(ByteBuffer(string: #"{"items":[{"id":"native-second"}],"total":2,"limit":2,"offset":1}"#))
            ),
        ])
        try await managedChatGPTApplication(transport: transport, history: history).test(.router) { client in
            let first = try await client.execute(
                uri: "/backend-api/conversations?offset=0&limit=2&order=updated",
                method: .get,
                headers: chatGPTOwnerHeaders
            )
            let one = try chatJSONObject(Data(first.body.readableBytesView))
            #expect(
                (one["items"] as? [[String: Any]])?.compactMap { $0["id"] as? String } == [
                    pending.conversationID, "native-first",
                ]
            )
            #expect(one["total"] as? Int == 3)
            #expect(one["limit"] as? Int == 2)
            #expect(one["offset"] as? Int == 0)
            #expect(one["has_missing_conversations"] as? Bool == false)
            let second = try await client.execute(
                uri: "/backend-api/conversations?offset=2&limit=2&order=updated",
                method: .get,
                headers: chatGPTOwnerHeaders
            )
            let two = try chatJSONObject(Data(second.body.readableBytesView))
            #expect((two["items"] as? [[String: Any]])?.compactMap { $0["id"] as? String } == ["native-second"])
            #expect(two["offset"] as? Int == 2)
        }
        let urls = await transport.requests.map(\.url)
        #expect(urls.count == 2)
        #expect(urls.first?.contains("offset=0&limit=1") == true)
        #expect(urls.last?.contains("offset=1&limit=2") == true)
    }
}
