import Foundation

enum CodexProfileSignatureMatcher {
    static func matching(
        modelSlug: String?,
        catalogData: Data,
        nativeCatalogData: Data?,
        expected: CodexManagedProfileSignature,
        legacyIdentifiers: CodexManagedProfileSignature?
    ) throws -> CodexManagedProfileSignature? {
        for identifiers in [expected, legacyIdentifiers].compactMap(\.self) where identifiers.modelSlug == modelSlug {
            for candidate in [identifiers, try identifiers.withLegacyAutoReview()] {
                let catalog = try CodexCatalog.mergedData(
                    managedData: candidate.catalogData, nativeCatalogData: nativeCatalogData)
                if catalogData == catalog {
                    return candidate
                }
            }
        }
        return nil
    }
}
