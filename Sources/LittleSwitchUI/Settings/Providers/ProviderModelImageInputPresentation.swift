import Foundation
import LittleSwitchCommon
import LittleSwitchCore

struct ProviderModelImageInputPresentation: Equatable {
    let title: String
    let help: String

    static func make(
        provider: Provider,
        model: DiscoveredModel,
        learnedNative: Bool?,
        diagnostics: [ModelImageInputProbeDiagnostic] = [],
        locale: Locale = .current
    ) -> Self {
        let wire = ProviderResponsesWireResolver.resolve(provider: provider, learnedNative: learnedNative)
        let key = try? ModelImageInputPolicyResolver.key(provider: provider, modelID: model.id, wire: wire)
        let observation = provider.imageInputObservations.filter { $0.key == key }.max { $0.observedAt < $1.observedAt }
        let diagnostic = diagnostics.filter { $0.key == key }.max { $0.result.startedAt < $1.result.startedAt }
        var details = [wire == .responses ? "Responses" : "Chat Completions"]
        let title: String
        if let override = provider.imageInputOverride {
            title = L10n.string(override == .enabled ? "Images forced on" : "Images forced off", locale: locale)
            details.append(L10n.string("User override", locale: locale))
        } else if let observation {
            title = L10n.string(observation.verdict == .verified ? "Images verified" : "Images refused", locale: locale)
            details.append(
                L10n.string(
                    observation.source == .visualProbe ? "Visual check" : "Provider rejection", locale: locale))
            details.append(observation.observedAt.formatted(dateStyle(locale)))
        } else if let advertised = model.supportsImageInput {
            title = L10n.string(advertised ? "Images advertised" : "Text only advertised", locale: locale)
            details.append(L10n.string("Provider metadata", locale: locale))
        } else {
            title = L10n.string(diagnostic == nil ? "Image support unknown" : "Check inconclusive", locale: locale)
        }
        if let diagnostic {
            details.append(diagnostic.result.startedAt.formatted(dateStyle(locale)))
            details += diagnosticDetails(diagnostic.result, locale: locale)
        }
        details.append(L10n.string("Checks are cached for 7 days.", locale: locale))
        return Self(title: title, help: details.joined(separator: "\n"))
    }

    private static func dateStyle(_ locale: Locale) -> Date.FormatStyle {
        .dateTime.locale(locale).year().month().day().hour().minute()
    }

    private static func diagnosticDetails(_ result: ModelImageInputProbeResult, locale: Locale) -> [String] {
        var details: [String] = []
        if case .inconclusive(let reason) = result.outcome {
            details.append(reasonTitle(reason, locale: locale))
        }
        let duration = result.durationSeconds.formatted(.number.locale(locale).precision(.fractionLength(2)))
        details.append(L10n.string("Duration: \(duration) s", locale: locale))
        if let usage = result.usage {
            details.append(
                L10n.string(
                    "Input: \(usage.inputTokens), output: \(usage.outputTokens), total: \(usage.totalTokens) tokens",
                    locale: locale))
        } else {
            details.append(L10n.string("Usage unavailable", locale: locale))
        }
        return details
    }

    private static func reasonTitle(_ reason: ModelImageProbeInconclusiveReason, locale: Locale) -> String {
        switch reason {
        case .wrongAnswer: L10n.string("The visual answer did not match", locale: locale)
        case .incompleteResponse: L10n.string("The check returned an incomplete answer", locale: locale)
        case .invalidResponse: L10n.string("The check returned an unreadable answer", locale: locale)
        case .routeUnavailable: L10n.string("The model route was unavailable", locale: locale)
        case .transport: L10n.string("The check could not reach the provider", locale: locale)
        case .timeout: L10n.string("Check timed out", locale: locale)
        case .sizeLimit: L10n.string("The check exceeded its size limit", locale: locale)
        case .httpStatus(let status): L10n.string("The check returned HTTP \(status)", locale: locale)
        }
    }
}
