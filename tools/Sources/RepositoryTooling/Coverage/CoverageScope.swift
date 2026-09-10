import Foundation

package struct CoverageScope: Equatable, Sendable {
    package let all: [String]
    package let measured: [String]
    package let excluded: [CoverageExclusion]

    init(sources: [String], exclusions: [CoverageExclusion], manifestPath: String) throws {
        let discovered = Set(sources)
        for exclusion in exclusions where !discovered.contains(exclusion.path) {
            throw CoverageValidationError(
                "\(manifestPath): exclusion is not a discovered production Swift source: \(exclusion.path)\n"
                    + "Exclusion rationale: \(exclusion.rationale)")
        }
        let excludedPaths = Set(exclusions.map(\.path))
        all = sources.sorted()
        measured = all.filter { !excludedPaths.contains($0) }
        excluded = exclusions
    }
}
