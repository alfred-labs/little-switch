import Foundation
import LittleSwitchCommon
import LittleSwitchSearch

/// Durable input stays in Codex. Only the per-provider request copy is filtered;
/// compaction selection always receives the original history and its provenance.
package struct PreparedGatewayResponses {
    let body: Data
    let compaction: ResponsesCompactionPlan?
    let webSearch: PreparedResponsesWebSearchRequest?

    package init(body: Data, target: CodexModelTarget, configuration: WebSearchConfiguration) throws {
        compaction = try ResponsesCompactionPlan.prepare(body: body, providerID: target.provider.id)
        let normalized = try ResponsesProviderState.normalize(body: body, providerID: target.provider.id)
        self.body = normalized
        webSearch =
            try compaction == nil
            ? OpenAIResponsesWebSearch.prepare(
                body: normalized, targetModel: target.model.id, configuration: configuration)
            : nil
    }
}
