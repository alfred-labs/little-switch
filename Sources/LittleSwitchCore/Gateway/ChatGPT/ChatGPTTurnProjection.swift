import Foundation
import NIOCore

/// Owns the mutable codec while the provider writes through a Sendable adapter.
/// Successful terminal output is held until EOF validation and durable storage.
actor ChatGPTTurnProjection {
    private let pending: ChatGPTPendingTurn
    private let model: String
    private let owner: String
    private let history: ChatGPTHistoryStore
    private let channel: ChatGPTStreamChannel
    private var stream: ChatGPTConversationStream
    private var terminal = Data()
    private var finished = false

    init(
        pending: ChatGPTPendingTurn,
        model: String,
        owner: String,
        history: ChatGPTHistoryStore,
        channel: ChatGPTStreamChannel
    ) {
        self.pending = pending
        self.model = model
        self.owner = owner
        self.history = history
        self.channel = channel
        stream = ChatGPTConversationStream(
            conversationID: pending.conversationID,
            message: .init(id: pending.assistantID, parentID: pending.parentID),
            model: model,
            timestamp: pending.timestamp,
            title: pending.title
        )
    }

    func initial() throws -> Data { try snapshot(text: "", status: .inProgress) }

    func append(_ buffer: ByteBuffer) async throws {
        guard !finished else { throw ChatGPTConversationError.invalidStream }
        let data = try stream.append(buffer)
        try await update()
        if stream.completed { terminal.append(data) } else if !data.isEmpty { try await channel.send(data) }
    }

    func finish() async throws {
        guard !finished else { throw ChatGPTConversationError.invalidStream }
        terminal.append(try stream.finish())
        try await update()
        try await history.finish(
            conversationID: pending.conversationID,
            owner: owner,
            assistantID: pending.assistantID,
            status: .finishedSuccessfully,
            now: Date().timeIntervalSince1970
        )
        finished = true
        if !terminal.isEmpty { try await channel.send(terminal) }
    }

    func fail(cancelled: Bool) async {
        guard !finished else {
            await channel.cancel()
            return
        }
        finished = true
        let status: ChatGPTNativeMessage.Status = cancelled ? .cancelled : .failed
        try? await update()
        try? await history.finish(
            conversationID: pending.conversationID,
            owner: owner,
            assistantID: pending.assistantID,
            status: status,
            now: Date().timeIntervalSince1970
        )
        if cancelled {
            await channel.cancel()
            return
        }
        do {
            let stored = try await history.conversation(id: pending.conversationID, owner: owner)
            let text = stored.nodes[pending.assistantID]?.text ?? ""
            var output = try snapshot(text: text, status: status)
            output.append(
                try event([
                    ChatGPTNativeContract.EventField.conversationId.rawValue: pending.conversationID,
                    ChatGPTNativeContract.EventField.error.rawValue: [
                        ChatGPTNativeContract.EventField.code.rawValue: ChatGPTNativeContract.ErrorCode.serverError
                            .rawValue,
                        ChatGPTNativeContract.EventField.message.rawValue:
                            "The local model response could not be completed",
                    ],
                ])
            )
            output.append(Data("data: [DONE]\n\n".utf8))
            try await channel.send(output)
            await channel.finish()
        } catch { await channel.cancel() }
    }

    private func update() async throws {
        try await history.update(
            conversationID: pending.conversationID,
            owner: owner,
            assistantID: pending.assistantID,
            text: stream.text
        )
    }

    private func snapshot(text: String, status: ChatGPTNativeMessage.Status) throws -> Data {
        try event([
            ChatGPTNativeContract.EventField.conversationId.rawValue: pending.conversationID,
            ChatGPTNativeContract.EventField.message.rawValue: ChatGPTNativeMessage.assistantRecord(
                identity: .init(id: pending.assistantID, parentID: pending.parentID),
                model: model,
                text: text,
                timestamp: pending.timestamp,
                status: status
            ),
        ])
    }

    private func event(_ object: [String: Any]) throws -> Data {
        var data = Data("data: ".utf8)
        data.append(try JSONSerialization.data(withJSONObject: object))
        data.append(Data("\n\n".utf8))
        return data
    }
}
