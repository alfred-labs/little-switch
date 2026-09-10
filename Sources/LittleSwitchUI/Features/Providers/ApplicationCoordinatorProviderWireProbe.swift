import Foundation
import LittleSwitchCore

extension ApplicationCoordinator {
    /// The route probe for this save. The previous probe survives while the
    /// endpoint and its credential are unchanged — a rename or a tuning edit
    /// must not re-probe — and a changed endpoint probes with zero-token
    /// requests that no firewall answer can turn into routing evidence.
    /// Throws only on cancellation: a cancelled save must not continue as if
    /// its probe had run.
    package func wireProbeForSave(
        provider: Provider,
        previous: Provider?,
        credentialChanged: Bool,
        secret: String?
    ) async throws -> ProviderWireProbe {
        let endpointUnchanged = previous?.baseURL == provider.baseURL
        let reusesPreviousProbe = endpointUnchanged && !credentialChanged
        if reusesPreviousProbe, let probe = previous?.wireProbe {
            return probe
        }
        return try await providerWireProber.probe(provider: provider, secret: secret)
    }

    /// The behavioral namespace probe for this save. It reuses the previous
    /// verdict under the same policy as the wire probe — endpoint and
    /// credential unchanged — plus one more condition: the probe records the
    /// model it ran on, and a different first model means a different
    /// backend that must be measured again. The probe needs a model, so it
    /// runs after discovery and skips a route the wire probe proved absent.
    /// Like the wire probe it throws only on cancellation.
    package func namespaceProbeForSave(
        provider: Provider,
        previous: Provider?,
        credentialChanged: Bool,
        secret: String?,
        wireProbe: ProviderWireProbe?
    ) async throws -> ProviderNamespaceProbe? {
        let firstModel = provider.models.first?.id
        let endpointUnchanged = previous?.baseURL == provider.baseURL
        if endpointUnchanged && !credentialChanged, let cached = previous?.namespaceProbe {
            if cached.model == firstModel {
                return cached
            }
        }
        guard wireProbe?.responsesRouteAbsent != true, let firstModel else {
            return nil
        }
        return try await providerNamespaceProber.probe(
            provider: provider,
            secret: secret,
            model: firstModel
        )
    }

    /// Seeds the Responses ledger from a committed save's probe. Only an
    /// absent `/v1/responses` is conclusive enough to teach — lenient front
    /// doors answer 200/400 to every path, so a probe "available" is display
    /// evidence, never routing evidence — and only after the save persisted:
    /// a failed or superseded save must not reroute live traffic on facts
    /// from a configuration that never landed.
    package func seedResponsesCapability(
        from probe: ProviderWireProbe?,
        providerID: UUID
    ) async {
        guard probe?.responsesRouteAbsent == true else {
            return
        }
        await responsesCapabilities.record(
            providerID: providerID,
            supportsNative: false
        )
    }
}
