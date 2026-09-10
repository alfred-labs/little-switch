/// A bounded behavioral namespace diagnostic for a provider's Responses
/// route. Implementations preserve cancellation and classify every
/// inconclusive failure as `.unknown` rather than evidence.
package protocol ProviderNamespaceProbing: Sendable {
    func probe(
        provider: Provider,
        secret: String?,
        model: String
    ) async throws -> ProviderNamespaceProbe
}
