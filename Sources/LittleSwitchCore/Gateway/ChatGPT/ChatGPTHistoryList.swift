import Foundation
import Hummingbird

/// A stable local prefix makes offset pagination composable without downloading
/// the account's entire native history or dropping older native conversations.
struct ChatGPTHistoryList {
    private typealias Field = ChatGPTNativeContract.HistoryField

    let offset: Int
    let limit: Int
    let archived: Bool
    let starred: Bool?
    let includesLocal: Bool
    private let components: URLComponents

    init(url: String) throws {
        guard let components = URLComponents(string: url) else { throw ChatGPTConversationError.invalidRequest }
        let items = components.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count else { throw ChatGPTConversationError.invalidRequest }
        let values = Dictionary(uniqueKeysWithValues: items.compactMap { item in item.value.map { (item.name, $0) } })
        guard let offset = Int(values[Field.offset.rawValue] ?? "0"), offset >= 0,
            offset <= Int.max - 100,
            let limit = Int(values[Field.limit.rawValue] ?? "20"),
            (1...100).contains(limit)
        else { throw ChatGPTConversationError.invalidRequest }
        self.offset = offset
        self.limit = limit
        archived = try Self.boolean(values[Field.isArchived.rawValue]) ?? false
        starred = try Self.boolean(values[Field.isStarred.rawValue])
        includesLocal =
            values[Field.conversationOrigin.rawValue] == nil
            || values[Field.conversationOrigin.rawValue]
                == ChatGPTNativeContract.Origin.chatgpt.rawValue
        self.components = components
    }

    func nativeURL(localCount: Int) throws -> String {
        let localOnPage = max(0, min(limit, localCount - offset))
        let replacements = [
            Field.offset.rawValue: String(max(0, offset - localCount)),
            Field.limit.rawValue: String(max(1, limit - localOnPage)),
        ]
        var result = components
        var items = components.queryItems ?? []
        for name in [
            Field.offset.rawValue,
            Field.limit.rawValue,
        ] {
            if let index = items.firstIndex(where: { $0.name == name }) {
                items[index].value = replacements[name]
            } else {
                items.append(URLQueryItem(name: name, value: replacements[name]))
            }
        }
        result.queryItems = items
        guard let url = result.string else { throw ChatGPTConversationError.invalidRequest }
        return url
    }

    func merge(nativeData: Data, local: [ChatGPTStoredConversation]) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: nativeData) as? [String: Any],
            let native = object[Field.items.rawValue] as? [[String: Any]]
        else { throw ChatGPTConversationError.invalidStream }
        let localPage = Array(local.dropFirst(min(offset, local.count)).prefix(limit))
        let summaries = try localPage.map { try JSONSerialization.jsonObject(with: $0.summaryData()) }
        object[Field.items.rawValue] =
            summaries + Array(native.prefix(limit - localPage.count))
        if let total = object[Field.total.rawValue] as? Int, total >= 0, total <= Int.max - local.count {
            object[Field.total.rawValue] = total + local.count
            if object[Field.hasMore.rawValue] != nil {
                object[Field.hasMore.rawValue] = offset + limit < total + local.count
            }
        }
        object[Field.offset.rawValue] = offset
        object[Field.limit.rawValue] = limit
        return try JSONSerialization.data(withJSONObject: object)
    }

    private static func boolean(_ value: String?) throws -> Bool? {
        switch value {
        case nil: nil
        case "true", "1": true
        case "false", "0": false
        default: throw ChatGPTConversationError.invalidRequest
        }
    }
}

extension ChatGPTGatewayResponder {
    func historyListResponse(_ request: Request, url: String, body: Data) async throws -> Response? {
        guard request.method == .get, request.uri.path == "/backend-api/conversations", let history else { return nil }
        let owner = try ChatGPTRequestBoundary.accountPartition(headers: request.headers)
        let page = try ChatGPTHistoryList(url: url)
        guard page.includesLocal else { return nil }
        let local = await history.list(owner: owner, archived: page.archived, starred: page.starred)
        guard !local.isEmpty else { return nil }
        var forwarded = nativeRequest(request, url: try page.nativeURL(localCount: local.count), body: body)
        forwarded.headers.remove(name: "if-none-match")
        forwarded.headers.remove(name: "if-modified-since")
        let upstream = try await transport.execute(forwarded)
        guard upstream.status == .ok else {
            if [301, 302, 303, 307, 308].contains(upstream.status.code) {
                return try errorResponse(.badGateway, "The ChatGPT backend requested an unsupported redirect")
            }
            return nativeResponse(upstream)
        }
        let data = Data(try await upstream.body.collect(upTo: 8 * 1_024 * 1_024).readableBytesView)
        return try nativeJSONResponse(page.merge(nativeData: data, local: local), headers: upstream.headers)
    }
}
