import Foundation

/// Cache retention belongs to the socket, never to a provider or persistent store.
struct ResponsesWebSocketHistoryCache: Sendable {
    struct Entry: Sendable {
        let streamID: String?
        let input: ResponsesWebSocketInput
        let retainedBytes: Int
    }

    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private var retainedBytes = 0

    subscript(responseID: String) -> Entry? { entries[responseID] }

    mutating func touch(_ responseID: String) {
        order.removeAll { $0 == responseID }
        order.append(responseID)
    }

    mutating func evictParent(_ responseID: String?, streamID: String?) {
        guard let responseID, let entry = entries[responseID], entry.streamID == streamID else { return }
        remove(responseID)
    }

    mutating func store(
        responseID: String, streamID: String?, input: ResponsesWebSocketInput, maximumBytes: Int
    ) {
        for (identifier, entry) in entries where entry.streamID == streamID { remove(identifier) }
        // A provider reusing another lane's ID makes lineage ambiguous. Both
        // clients must replay rather than silently acquire the wrong context.
        if entries[responseID] != nil {
            remove(responseID)
            return
        }
        let bytes = input.data.count + responseID.utf8.count + (streamID?.utf8.count ?? 0)
        guard bytes <= maximumBytes else { return }
        while retainedBytes > maximumBytes - bytes, let oldest = order.first { remove(oldest) }
        entries[responseID] = Entry(streamID: streamID, input: input, retainedBytes: bytes)
        retainedBytes += bytes
        touch(responseID)
    }

    private mutating func remove(_ responseID: String) {
        if let entry = entries.removeValue(forKey: responseID) { retainedBytes -= entry.retainedBytes }
        order.removeAll { $0 == responseID }
    }
}
