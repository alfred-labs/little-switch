import LittleSwitchCommon

package protocol ModelImageInputProbing: Sendable {
    func probe(
        provider: Provider,
        model: DiscoveredModel,
        wire: ModelImageInputWire,
        secret: String?
    ) async throws -> ModelImageInputProbeResult
}
