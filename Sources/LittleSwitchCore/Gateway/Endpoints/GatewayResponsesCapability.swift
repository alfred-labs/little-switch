import Foundation
import LittleSwitchCommon

extension GatewayResponder {
    /// Chooses the wire for a provider: a user override wins, then a learned
    /// native verdict, then native `/v1/responses` — the OpenAI-compatible
    /// default. No base-URL special case: the save-time probe learns absent
    /// routes before the first request (z.ai seeds the adapter at save), and
    /// the runtime 404 fallback is the safety net for unprobed providers.
    package func resolvesChatCompletionsAdapter(
        _ provider: Provider
    ) async -> Bool {
        let learned = await state.responsesCapabilities.verdict(for: provider.id)
        return ProviderResponsesWireResolver.resolve(provider: provider, learnedNative: learned) == .chatCompletions
    }

    /// Classifies a native `/v1/responses` attempt so later requests skip the
    /// failed wire: 2xx proves the route, HTTP 404/405 prove its absence, and
    /// other statuses say nothing. WS rejection frames are not route evidence;
    /// synthetic warmups provide no evidence, regardless of their status.
    package func recordResponsesCapability(
        providerID: UUID,
        status: UInt,
        origin: GatewayModelExchange.Origin = .http
    ) async {
        guard origin != .synthetic else { return }
        if status == 404 || status == 405 {
            guard origin == .http else { return }
            await state.responsesCapabilities.record(
                providerID: providerID,
                supportsNative: false
            )
        } else if (200..<300).contains(status) {
            await state.responsesCapabilities.record(
                providerID: providerID,
                supportsNative: true
            )
        }
    }

    /// The web-search turn executors teach through here: only a native
    /// attempt may instruct the ledger — a 2xx from the chat-completions
    /// adapter proves the provider answers, not that `/v1/responses` exists,
    /// and recording it would flip the next request back onto the missing
    /// route.
    package func recordResponsesCapability(
        context: GatewayResponsesWebSearchContext,
        status: UInt,
        origin: GatewayModelExchange.Origin = .http
    ) async {
        guard !context.needsChatCompletionsAdapter else {
            return
        }
        await recordResponsesCapability(
            providerID: context.target.provider.id,
            status: status,
            origin: origin
        )
    }

    /// The mirror lesson: a 404/405 answered on the adapter's own route
    /// proves `/v1/chat/completions` absent, so the provider must serve
    /// `/v1/responses` natively — without this, a stale adapter verdict
    /// could never relearn and every request would relay the 404.
    package func recordChatCompletionsRouteAbsent(
        providerID: UUID,
        status: UInt
    ) async {
        if status == 404 || status == 405 {
            await state.responsesCapabilities.record(
                providerID: providerID,
                supportsNative: true
            )
        }
    }

    /// Whether a failed native `/v1/responses` attempt should be retried
    /// through the chat-completions adapter. Only in automatic mode: a
    /// provider pinned to either wire relays its failures honestly instead
    /// of being silently rerouted.
    package func responsesAdapterFallbackApplies(
        status: UInt,
        provider: Provider,
        origin: GatewayModelExchange.Origin = .http
    ) -> Bool {
        origin == .http && (status == 404 || status == 405) && provider.responsesWireOverride == nil
    }
}
