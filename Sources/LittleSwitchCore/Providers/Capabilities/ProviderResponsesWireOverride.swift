/// Forces the wire Codex traffic uses for a provider, overriding the learned
/// Responses capability. Nil (the default) keeps automatic detection:
/// native `/v1/responses` first, chat-completions adapter once a probe or a
/// 404 proves the route absent.
public enum ProviderResponsesWireOverride: String, Codable, Sendable {
    case native
    case chatCompletions
}
