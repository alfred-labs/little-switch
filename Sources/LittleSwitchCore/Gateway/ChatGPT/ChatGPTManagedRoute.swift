import Foundation
import HTTPTypes
import LittleSwitchCommon

/// Classify before any native forwarding: a removed model or unknown local
/// conversation must never send local history to the native service.
enum ChatGPTManagedRoute {
    private typealias Field = ChatGPTNativeContract.ConversationField

    case native
    case prepare(model: String?, conversationID: String?, initialize: Bool)
    case generate(ChatGPTConversationRequest)
    case detail(String)
    case status(String)
    case stop(String)
    case patch(String, ChatGPTHistoryPatch)
    case remove(String)

    static func resolve(path uri: String, method: HTTPRequest.Method, body: Data, models: Set<String>) throws -> Self {
        let components = URLComponents(string: "https://chatgpt.com" + uri)
        if components?.queryItems?.contains(where: { $0.value.map(ChatGPTConversationID.isOwned) ?? false }) == true {
            throw ChatGPTHistoryError.notFound
        }
        let path = String(uri.split(separator: "?", maxSplits: 1)[0])
        let document = try? JSONSerialization.jsonObject(with: body)
        let object = document as? [String: Any] ?? [:]
        let model =
            object[Field.model.rawValue] as? String ?? object[
                Field.requestedDefaultModel.rawValue] as? String
        let conversation = (object[Field.conversationId.rawValue] as? String)?
            .lowercased()
        let managedModel =
            model.map { models.contains($0) || ManagedModelIdentifier.usesCanonicalNamespace($0) } ?? false
        let owned = conversation.map(ChatGPTConversationID.isOwned) ?? false
        if method == .post, managedModel || owned {
            return try postRoute(
                path: path,
                body: body,
                conversation: conversation,
                object: object,
                models: models
            )
        }
        let segments = path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        if segments.count >= 3, segments[0] == "backend-api", segments[1] == "conversation" {
            let identifierIndex = segments[2] == "id" ? 3 : 2
            if segments.count > identifierIndex, ChatGPTConversationID.isOwned(segments[identifierIndex]) {
                let id = segments[identifierIndex].lowercased()
                let suffix = Array(segments.dropFirst(identifierIndex + 1))
                if suffix.isEmpty {
                    switch method {
                    case .get: return .detail(id)
                    case .delete: return .remove(id)
                    case .patch:
                        let changes = try patch(object)
                        let visible = object[Field.isVisible.rawValue]
                        if let visible, try !ChatGPTRequestValidation.boolean(visible) {
                            return .remove(id)
                        }
                        return .patch(id, changes)
                    default: break
                    }
                }
                if suffix == ["stream_status"], method == .get { return .status(id) }
                if suffix == ["rename"], method == .post { return .patch(id, try patch(object)) }
                throw ChatGPTHistoryError.notFound
            }
        }
        let containsLocal =
            segments.contains(where: ChatGPTConversationID.isOwned) || document.map(containsOwnedID) == true
        if managedModel || owned || containsLocal {
            throw ChatGPTHistoryError.notFound
        }
        return .native
    }

    private static func postRoute(
        path: String,
        body: Data,
        conversation: String?,
        object: [String: Any],
        models: Set<String>
    ) throws -> Self {
        let model =
            object[Field.model.rawValue] as? String ?? object[
                Field.requestedDefaultModel.rawValue] as? String
        let owned = conversation.map(ChatGPTConversationID.isOwned) ?? false
        switch path {
        case "/backend-api/conversation/init", "/backend-api/f/conversation/prepare":
            if let model, !models.contains(model) { throw ChatGPTHistoryError.notFound }
            if let conversation, !ChatGPTConversationID.isOwned(conversation) {
                throw ChatGPTConversationError.unsupportedRequest
            }
            try ChatGPTRequestValidation.validateContext(object)
            return .prepare(model: model, conversationID: conversation, initialize: path.hasSuffix("/init"))
        case "/backend-api/f/conversation", "/backend-api/conversation":
            let request = try ChatGPTConversationRequest.decode(body)
            guard models.contains(request.model) else {
                if owned { throw ChatGPTConversationError.unsupportedRequest }
                throw ChatGPTHistoryError.notFound
            }
            if let id = request.conversationID, !ChatGPTConversationID.isOwned(id) {
                throw ChatGPTConversationError.unsupportedRequest
            }
            return .generate(request)
        case "/backend-api/stop_conversation":
            guard let conversation, ChatGPTConversationID.isOwned(conversation) else {
                throw ChatGPTHistoryError.notFound
            }
            return .stop(conversation)
        default: throw ChatGPTHistoryError.notFound
        }
    }

    private static func patch(_ object: [String: Any]) throws -> ChatGPTHistoryPatch {
        let allowed: Set<String> = [
            Field.title.rawValue,
            Field.isArchived.rawValue,
            Field.isStarred.rawValue,
            Field.currentNodeId.rawValue,
            Field.isVisible.rawValue,
        ]
        guard Set(object.keys).isSubset(of: allowed), !object.isEmpty else {
            throw ChatGPTConversationError.unsupportedRequest
        }
        if let value = object[Field.title.rawValue], !(value is String) {
            throw ChatGPTConversationError.invalidRequest
        }
        if let visible = object[Field.isVisible.rawValue] {
            _ = try ChatGPTRequestValidation.boolean(visible)
        }
        let node = try object[Field.currentNodeId.rawValue].map(
            ChatGPTRequestValidation.identifier)
        return ChatGPTHistoryPatch(
            title: object[Field.title.rawValue] as? String,
            archived: try object[Field.isArchived.rawValue].map(
                ChatGPTRequestValidation.boolean),
            starred: try object[Field.isStarred.rawValue].map(
                ChatGPTRequestValidation.boolean),
            currentNodeID: node
        )
    }

    private static func containsOwnedID(_ value: Any) -> Bool {
        if let string = value as? String { return ChatGPTConversationID.isOwned(string) }
        if let array = value as? [Any] { return array.contains(where: containsOwnedID) }
        if let object = value as? [String: Any] { return object.values.contains(where: containsOwnedID) }
        return false
    }
}
