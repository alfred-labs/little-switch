import AsyncHTTPClient
import Foundation
import LittleSwitchCommon

extension GatewayResponder {
    /// Probe only exchanges that actually declare custom tools, and never the
    /// native OpenAI passthrough. Admission is already held by this model turn.
    func customToolProjection(
        request: HTTPClientRequest, body: Data, traffic: TrafficUpstreamRequest?, wire: ProviderToolContract.Wire
    ) async throws -> CustomToolProjection {
        guard wire != .anthropic, let traffic, let cache = state.customToolCapabilities else {
            return try CustomToolProjection.prepare(body: body, wire: wire, adapt: false)
        }
        let candidate = try CustomToolProjection.prepare(body: body, wire: wire, adapt: true)
        guard !candidate.isIdentity else { return candidate }
        let capture: GatewayRoutingCapture
        if let customToolRoutingCapture {
            capture = customToolRoutingCapture
        } else {
            capture = await state.routingCapture()
        }
        guard let revision = capture.providerRevision(for: traffic.providerID) else {
            throw GatewayAdmissionError.invalidated
        }
        try await state.requireCustomToolRevision(revision, providerID: traffic.providerID)
        let key = CustomToolCapabilityKey(
            providerID: traffic.providerID,
            modelID: traffic.modelID,
            endpoint: request.url,
            wire: wire == .responses ? "responses" : "chatCompletions")
        let prober = CustomToolCapabilityProber(transport: transport)
        let mode = try await cache.mode(for: key) {
            try await state.requireCustomToolRevision(revision, providerID: traffic.providerID)
            let result = try await prober.probe(template: request, modelID: traffic.modelID, wire: wire)
            try await state.requireCustomToolRevision(revision, providerID: traffic.providerID)
            return result
        }
        try Task.checkCancellation()
        try await state.requireCustomToolRevision(revision, providerID: traffic.providerID)
        return mode == .functionEnvelope
            ? candidate : try CustomToolProjection.prepare(body: body, wire: wire, adapt: false)
    }
}
