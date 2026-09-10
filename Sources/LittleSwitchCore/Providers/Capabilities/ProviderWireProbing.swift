/// A bounded endpoint-presence diagnostic, independent of model capabilities.
/// Implementations preserve cancellation and represent other inconclusive
/// failures as unknown routes rather than treating them as routing evidence.
package protocol ProviderWireProbing: Sendable {
    func probe(provider: Provider, secret: String?) async throws -> ProviderWireProbe
}
