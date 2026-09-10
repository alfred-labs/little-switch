import Foundation

package struct PreparedResponsesChatCompletionsRequest: Equatable, Sendable {
    let upstreamBody: Data
    let originalBody: Data
    let originalModel: String
    let streaming: Bool
    let toolBindings: [String: ResponsesToolNamespaces.Binding]
    var droppedMailCount: Int = 0
    let toolSearchContract: ResponsesClientToolSearchContract?

    init(
        upstreamBody: Data,
        originalBody: Data,
        originalModel: String,
        streaming: Bool,
        toolBindings: [String: ResponsesToolNamespaces.Binding] = [:],
        droppedMailCount: Int = 0,
        toolSearchContract: ResponsesClientToolSearchContract? = nil
    ) {
        self.upstreamBody = upstreamBody
        self.originalBody = originalBody
        self.originalModel = originalModel
        self.streaming = streaming
        self.toolBindings = toolBindings
        self.droppedMailCount = droppedMailCount
        self.toolSearchContract = toolSearchContract
    }
}
