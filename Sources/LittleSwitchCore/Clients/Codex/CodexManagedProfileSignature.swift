import Foundation

public struct CodexManagedProfileSignature: Equatable, Sendable {
    public let modelSlug: String
    public let catalogData: Data
    public let maximumConcurrentThreadsPerSession: Int?
    /// Nil identifies a legacy profile that does not own the user's search mode.
    public let webSearchMode: String?

    public static func resolve(
        providers: [Provider],
        configuration: CodexConfiguration,
        nativeCatalogData: Data? = nil
    ) throws -> CodexManagedProfileSignature {
        let normalized = configuration.normalized(for: providers)
        guard
            let defaultModel = normalized.defaultModel,
            let provider = providers.first(where: { $0.id == defaultModel.providerID }),
            let model = provider.models.first(where: { $0.id == defaultModel.modelID })
        else {
            throw CodexCatalog.Error.empty
        }
        return CodexManagedProfileSignature(
            modelSlug: CodexCatalog.slug(
                for: CodexModelTarget(provider: provider, model: model)
            ),
            catalogData: try CodexCatalog.encode(
                providers: providers,
                configuration: normalized,
                nativeCatalogData: nativeCatalogData
            ),
            maximumConcurrentThreadsPerSession: max(1, provider.maximumParallelRequests),
            webSearchMode: CodexTOMLEditor.defaultWebSearchMode
        )
    }

    public func withoutNativeConcurrency() -> CodexManagedProfileSignature {
        CodexManagedProfileSignature(
            modelSlug: modelSlug,
            catalogData: catalogData,
            maximumConcurrentThreadsPerSession: nil,
            webSearchMode: webSearchMode
        )
    }

    package func withLegacyAutoReview() throws -> CodexManagedProfileSignature {
        CodexManagedProfileSignature(
            modelSlug: modelSlug,
            catalogData: try CodexCatalog.legacyAutoReviewData(catalogData),
            maximumConcurrentThreadsPerSession: maximumConcurrentThreadsPerSession,
            webSearchMode: webSearchMode
        )
    }

    public func withoutManagedWebSearch() -> CodexManagedProfileSignature {
        CodexManagedProfileSignature(
            modelSlug: modelSlug,
            catalogData: catalogData,
            maximumConcurrentThreadsPerSession: maximumConcurrentThreadsPerSession,
            webSearchMode: nil
        )
    }

    private init(
        modelSlug: String,
        catalogData: Data,
        maximumConcurrentThreadsPerSession: Int?,
        webSearchMode: String?
    ) {
        self.modelSlug = modelSlug
        self.catalogData = catalogData
        self.maximumConcurrentThreadsPerSession = maximumConcurrentThreadsPerSession
        self.webSearchMode = webSearchMode
    }
}
