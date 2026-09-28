import Foundation

package struct ResponsesWebSocketTurn: Sendable {
    package let id: UUID
    package let streamID: String?
    package let body: Data
    package let generate: Bool
    package let previousResponseID: String?
    package let replacesHistory: Bool
    package let incrementalInput: Data?

    package init(
        id: UUID,
        streamID: String?,
        body: Data,
        generate: Bool,
        previousResponseID: String?,
        replacesHistory: Bool,
        incrementalInput: Data? = nil
    ) {
        self.id = id
        self.streamID = streamID
        self.body = body
        self.generate = generate
        self.previousResponseID = previousResponseID
        self.replacesHistory = replacesHistory
        self.incrementalInput = incrementalInput
    }
}

package struct ResponsesWebSocketCompletion: Sendable {
    package let responseID: String
    package let output: Data

    package init(responseID: String, output: Data) {
        self.responseID = responseID
        self.output = output
    }
}
