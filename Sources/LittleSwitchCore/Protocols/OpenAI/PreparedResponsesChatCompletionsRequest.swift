import Foundation

package struct PreparedResponsesChatCompletionsRequest: Equatable, Sendable {
    let upstreamBody: Data
    let originalBody: Data
    let originalModel: String
    let streaming: Bool
    let toolBindings: [String: ResponsesToolNamespaces.Binding]
    /// The bindings the request's own namespace declarations created — the
    /// resolution set for provider near-misses, inherited from the search
    /// bridge when it flattened first.
    let declaredToolBindings: [String: ResponsesToolNamespaces.Binding]
    var droppedMailCount: Int = 0
    let toolSearchContract: ResponsesClientToolSearchContract?

    init(
        upstreamBody: Data,
        originalBody: Data,
        originalModel: String,
        streaming: Bool,
        toolBindings: [String: ResponsesToolNamespaces.Binding] = [:],
        declaredToolBindings: [String: ResponsesToolNamespaces.Binding] = [:],
        droppedMailCount: Int = 0,
        toolSearchContract: ResponsesClientToolSearchContract? = nil
    ) {
        self.upstreamBody = upstreamBody
        self.originalBody = originalBody
        self.originalModel = originalModel
        self.streaming = streaming
        self.toolBindings = toolBindings
        self.declaredToolBindings = declaredToolBindings
        self.droppedMailCount = droppedMailCount
        self.toolSearchContract = toolSearchContract
    }
}
