import Foundation

package struct ResponsesPublicStreamSession: Sendable {
    enum Configuration: Sendable {
        case webSearch(PreparedResponsesWebSearchRequest)
        case chatCompletions(PreparedResponsesChatCompletionsRequest)

        var originalModel: String {
            switch self {
            case .webSearch(let prepared):
                prepared.originalModel
            case .chatCompletions(let prepared):
                prepared.originalModel
            }
        }

        var originalBody: Data {
            switch self {
            case .webSearch(let prepared):
                prepared.originalBody
            case .chatCompletions(let prepared):
                prepared.originalBody
            }
        }

        var toolSearchContract: ResponsesClientToolSearchContract? {
            switch self {
            case .webSearch(let prepared):
                prepared.toolSearchContract
            case .chatCompletions(let prepared):
                prepared.toolSearchContract
            }
        }

        var privateSearchToolName: String? {
            switch self {
            case .webSearch(let prepared): prepared.privateToolName
            case .chatCompletions: nil
            }
        }
    }

    enum TerminalState: Sendable {
        case open
        case completed
        case failed
    }

    struct ContentMapping: Sendable {
        let publicIndex: Int
        let type: String
    }

    struct OutputMapping: Sendable {
        let id: String
        let type: String
        let name: String?
        let callID: String?
        let publicIndex: Int?
        let isPrivateSearch: Bool
        var toolSearchContract: ResponsesClientToolSearchContract?
        var nextContentIndex = 0
        var content: [Int: ContentMapping] = [:]
    }

    struct PendingSearch: Sendable {
        let id: String
        let query: String
        let outputIndex: Int
    }

    let configuration: Configuration
    var terminalState = TerminalState.open
    var started = false
    var providerTurnActive = false
    var providerOutput: [Int: OutputMapping] = [:]
    var nextSequenceNumber = 0
    var nextOutputIndex = 0
    var completedOutput: [Int: Data] = [:]
    var usedPublicItemIDs: Set<String> = []
    var pendingSearch: PendingSearch?
    var firstResponseJSON: Data?
    var publicResponseID: String?
    var publicCreatedAt: Int?
    var lastProviderTerminal: ResponsesStreamTerminal?

    package init(webSearch prepared: PreparedResponsesWebSearchRequest) {
        configuration = .webSearch(prepared)
    }

    package init(chatCompletions prepared: PreparedResponsesChatCompletionsRequest) {
        configuration = .chatCompletions(prepared)
    }

    /// Bindings captured when the native request was normalized; they restore
    /// the namespace pair on flattened provider calls.
    var nativeToolBindings: [String: ResponsesToolNamespaces.Binding] {
        guard case .webSearch(let prepared) = configuration else {
            return [:]
        }
        return prepared.toolBindings
    }

    /// The request's own declared bindings: the resolution set for provider
    /// near-misses on the native turn stream.
    var nativeDeclaredToolBindings: [String: ResponsesToolNamespaces.Binding] {
        guard case .webSearch(let prepared) = configuration else {
            return [:]
        }
        return prepared.declaredToolBindings
    }
}
