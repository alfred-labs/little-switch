import Foundation

@testable import LittleSwitchCore

extension CodexCatalog {
    /// Slug for a mapping that the given providers are known to expose.
    static func slug(for mapping: ModelMapping, in providers: [Provider]) -> String {
        guard let provider = providers.first(where: { $0.id == mapping.providerID }),
            let model = provider.models.first(where: { $0.id == mapping.modelID })
        else {
            preconditionFailure("mapping \(mapping) is not exposed by the given providers")
        }
        return slug(for: CodexModelTarget(provider: provider, model: model))
    }
}
