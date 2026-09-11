import Foundation

package struct PreparedResponsesChatCompletionsRequest: Equatable, Sendable {
    let upstreamBody: Data
    let originalBody: Data
    let originalModel: String
    let providerID: UUID?
    let streaming: Bool
    let toolBindings: [String: ResponsesToolNamespaces.Binding]
    /// The bindings the request's own namespace declarations created — the
    /// resolution set for provider near-misses, inherited from the search
    /// bridge when it flattened first.
    let declaredToolBindings: [String: ResponsesToolNamespaces.Binding]
    let toolNameCatalog: ProviderToolNameCatalog
    /// Only identities on the final selected provider request may be published.
    let allowedToolIdentities: Set<ProviderToolContractCatalog.Identity>
    var droppedMailCount: Int = 0
    let toolSearchContract: ResponsesClientToolSearchContract?

    init(
        upstreamBody: Data,
        originalBody: Data,
        originalModel: String,
        providerID: UUID? = nil,
        streaming: Bool,
        toolBindings: [String: ResponsesToolNamespaces.Binding] = [:],
        declaredToolBindings: [String: ResponsesToolNamespaces.Binding] = [:],
        toolNameCatalog: ProviderToolNameCatalog = .init(),
        allowedToolIdentities: Set<ProviderToolContractCatalog.Identity> = [],
        droppedMailCount: Int = 0,
        toolSearchContract: ResponsesClientToolSearchContract? = nil
    ) {
        self.upstreamBody = upstreamBody
        self.originalBody = originalBody
        self.originalModel = originalModel
        self.providerID = providerID
        self.streaming = streaming
        self.toolBindings = toolBindings
        self.declaredToolBindings = declaredToolBindings
        self.toolNameCatalog = toolNameCatalog
        self.allowedToolIdentities = allowedToolIdentities
        self.droppedMailCount = droppedMailCount
        self.toolSearchContract = toolSearchContract
    }
}
