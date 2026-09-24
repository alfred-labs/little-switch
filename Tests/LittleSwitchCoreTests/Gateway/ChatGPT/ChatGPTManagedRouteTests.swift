import Foundation
import HTTPTypes
import Testing

@testable import LittleSwitchCore

struct ChatGPTManagedRouteTests {
    @Test(arguments: ["/backend-api/models?flag", "/backend-api/%ZZ"])
    func nativePathsWithMissingQueryValuesOrInvalidEscapesStayNative(path: String) throws {
        let route = try ChatGPTManagedRoute.resolve(path: path, method: .get, body: Data(), models: [])
        guard case .native = route else {
            Issue.record("Native path was intercepted")
            return
        }
    }

    @Test func patchValidatesAndNormalizesCurrentNode() throws {
        let node = UUID().uuidString
        let route = try ChatGPTManagedRoute.resolve(
            path: "/backend-api/conversation/" + ChatGPTConversationID.make(),
            method: .patch,
            body: JSONEncoder().encode(["current_node_id": node]),
            models: [])
        guard case .patch(_, let changes) = route else {
            Issue.record("Owned node patch was not recognized")
            return
        }
        #expect(changes.currentNodeID == node.lowercased())
    }

    @Test func managedStopRequiresAnOwnedConversation() throws {
        #expect(throws: ChatGPTHistoryError.notFound) {
            try ChatGPTManagedRoute.resolve(
                path: "/backend-api/stop_conversation",
                method: .post,
                body: Data(#"{"model":"local"}"#.utf8),
                models: ["local"])
        }
    }
    @Test func nativePayloadWithScalarValuesStaysNative() throws {
        let route = try ChatGPTManagedRoute.resolve(
            path: "/backend-api/conversation/init",
            method: .post,
            body: Data(#"{"requested_default_model":"native","flags":[false,1,null]}"#.utf8),
            models: [])
        guard case .native = route else {
            Issue.record("Native metadata was intercepted")
            return
        }
    }

    @Test func localPreparationCannotImportANativeConversation() throws {
        #expect(throws: ChatGPTConversationError.unsupportedRequest) {
            try ChatGPTManagedRoute.resolve(
                path: "/backend-api/conversation/init",
                method: .post,
                body: JSONEncoder().encode(["model": "local", "conversation_id": UUID().uuidString]),
                models: ["local"])
        }
    }

    @Test func invalidTitleCannotRenameHistory() throws {
        #expect(throws: ChatGPTConversationError.invalidRequest) {
            try ChatGPTManagedRoute.resolve(
                path: "/backend-api/conversation/" + ChatGPTConversationID.make(),
                method: .patch,
                body: Data(#"{"title":42}"#.utf8),
                models: [])
        }
    }
    @Test func unsupportedBatchNeverForwardsLocalIdentifiers() throws {
        let id = ChatGPTConversationID.make()
        let data = try JSONEncoder().encode([id])
        #expect(throws: ChatGPTHistoryError.notFound) {
            try ChatGPTManagedRoute.resolve(
                path: "/backend-api/conversations/batch",
                method: .post,
                body: data,
                models: []
            )
        }
    }

    @Test(arguments: [#"{"is_visible":0}"#, #"{"is_visible":false,"unsupported":true}"#, #"{"is_visible":"false"}"#])
    func malformedDeleteCannotRemoveLocalHistory(body: String) throws {
        let expected: ChatGPTConversationError = body.contains("unsupported") ? .unsupportedRequest : .invalidRequest
        #expect(throws: expected) {
            try ChatGPTManagedRoute.resolve(
                path: "/backend-api/conversation/" + ChatGPTConversationID.make(),
                method: .patch,
                body: Data(body.utf8),
                models: []
            )
        }
    }
}
