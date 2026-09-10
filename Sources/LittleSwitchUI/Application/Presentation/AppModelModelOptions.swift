import Foundation
import LittleSwitchCore

/// Model catalogue projections shared by the Claude and Codex panes: the flat
/// option list, the exposed subset, and the per-provider grouping the exposed
/// list is rendered from.
@MainActor
extension AppModel {
    public var modelOptions: [ModelOption] {
        providers
            .flatMap { provider in
                provider.models.map { model in
                    ModelOption(
                        providerID: provider.id,
                        providerName: provider.name,
                        modelID: model.id
                    )
                }
            }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    public var codexExposedModelOptions: [ModelOption] {
        modelOptions.filter { isCodexModelExposed($0.mapping) }
    }

    var hasUnavailableCodexAutoReviewModel: Bool {
        configuration.codex.autoReviewModel != nil
            && configuration.codex.resolvedAutoReviewTarget(in: providers) == nil
    }

    /// Exposed-model rows grouped by the provider that serves them, in the
    /// order providers are configured. The list names each provider once
    /// instead of repeating it under every model.
    public var codexExposureGroups: [ModelOptionGroup] {
        let optionsByProvider = Dictionary(grouping: modelOptions, by: \.providerID)
        return providers.compactMap { provider in
            guard let options = optionsByProvider[provider.id], !options.isEmpty else {
                return nil
            }
            return ModelOptionGroup(
                providerID: provider.id,
                providerName: provider.name,
                options: options
            )
        }
    }
}
