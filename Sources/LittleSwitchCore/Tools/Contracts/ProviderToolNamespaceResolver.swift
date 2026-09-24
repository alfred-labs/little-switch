import Foundation

/// Resolves a flattened tool-call name a provider emitted against the
/// namespace children this request declared.
///
/// Providers that only implement plain function calling receive the flattened
/// `namespace__tool` declarations, and some then emit a near-miss instead of
/// the exact wire name (observed in production from one backend, four
/// variants in four requests: `spawn_agent`, `list_agents`,
/// `functions.collaboration.spawn_agent`,
/// `mcp__tools__collaboration_spawn_agent`). The tool contract still demands
/// an exactly declared identity, so the resolver maps a near-miss onto the
/// wire name it denotes; the caller re-validates that name against the
/// request's own declarations.
///
/// Resolution only recovers current namespace children and checks every plain
/// declaration for competing identities. Historical names reserve their exact
/// spelling without making a retired identity emittable. When the caller
/// supplies a namespace (a backend that natively restores the pair), only an exact pair match resolves:
/// fuzzy rules would second-guess a backend that already names its tools
/// precisely.
package struct ProviderToolNamespaceResolver: Sendable {
    private let exact: [String: ResponsesToolNamespaces.Binding]
    private let declaredNames: Set<String>
    private let plainNames: Set<String>
    private let historicalNames: Set<String>
    private let childNames: [Data: [String]]
    /// Last namespace segment → child name → the wire names that pair
    /// declares. Nested dictionaries keep the lookup collision-free without
    /// a key struct whose fields Periphery would flag as assign-only.
    private let namespacePairs: [Data: [Data: [String]]]

    package init(
        declaredBindings: [String: ResponsesToolNamespaces.Binding],
        nameCatalog: ProviderToolNameCatalog = .init()
    ) {
        let declaredNames = nameCatalog.declared.union(declaredBindings.keys)
        let plainNames = declaredNames.subtracting(declaredBindings.keys)
        var childNames = Dictionary(uniqueKeysWithValues: plainNames.map { (Data($0.utf8), [$0]) })
        var namespacePairs: [Data: [Data: [String]]] = [:]
        for name in plainNames {
            let tokens = Self.tokens(name)
            if tokens.count >= 2 {
                namespacePairs[Data(tokens[tokens.count - 2].utf8), default: [:]][
                    Data(tokens[tokens.count - 1].utf8), default: []
                ].append(
                    name)
            }
        }
        for (wireName, binding) in declaredBindings {
            childNames[Data(binding.name.utf8), default: []].append(wireName)
            let segments = binding.namespace.split(separator: ".")
            if let lastSegment = segments.last {
                namespacePairs[
                    Data(lastSegment.utf8),
                    default: [:]
                ][Data(binding.name.utf8), default: []].append(wireName)
            }
        }
        self.exact = declaredBindings
        self.declaredNames = declaredNames
        self.plainNames = plainNames
        self.historicalNames = nameCatalog.historical
        self.childNames = childNames
        self.namespacePairs = namespacePairs
    }

    /// The declared wire name the emitted name denotes, or nil when nothing
    /// matches unambiguously — callers keep their existing rejection.
    package func wireName(for emitted: String, namespace: String?) -> String? {
        if let namespace {
            // A backend that supplies the namespace has already decided the
            // identity; accept only the exact pair, never a fuzzy recovery.
            return exact.first { $0.value == ResponsesToolNamespaces.Binding(namespace: namespace, name: emitted) }?
                .key
        }
        if declaredNames.contains(where: { $0.utf8.elementsEqual(emitted.utf8) }) {
            return emitted
        }
        guard !historicalNames.contains(emitted) else {
            return nil
        }
        if let candidates = childNames[Data(emitted.utf8)] {
            // A complete child name is already the most specific match.
            // Ambiguity here must not select a different, shorter identity.
            return uniqueNamespaceCandidate(candidates)
        }
        if let candidates = tokenCandidates(emitted) {
            return uniqueNamespaceCandidate(candidates)
        }
        return resolvedBySuffix(emitted)
    }

    /// Restores the original pair without changing an exact plain identity.
    /// History can restore an exact spelling, but never participates in fuzzy
    /// resolution. An explicit pair is already an identity and stays intact.
    package func restoredBinding(
        for name: String,
        namespace: String? = nil,
        bindings: [String: ResponsesToolNamespaces.Binding]
    ) -> ResponsesToolNamespaces.Binding? {
        if let namespace {
            let binding = ResponsesToolNamespaces.Binding(namespace: namespace, name: name)
            return bindings.values.contains(binding) ? binding : nil
        }
        if declaredNames.contains(where: { $0.utf8.elementsEqual(name.utf8) }) {
            return Self.exactValue(name, in: exact)
        }
        if let binding = Self.exactValue(name, in: bindings) {
            return binding
        }
        guard let wireName = wireName(for: name, namespace: nil) else {
            return nil
        }
        return Self.exactValue(wireName, in: exact)
    }

    /// `functions.collaboration.spawn_agent`: split on `__` and `.` and match
    /// the trailing `lastNamespaceSegment + child` couple, uniquely.
    /// A matched but ambiguous pair is final; suffix recovery must not erase
    /// a competing qualified plain declaration.
    private func tokenCandidates(_ emitted: String) -> [String]? {
        let tokens = Self.tokens(emitted)
        guard tokens.count >= 2,
            let pair = namespacePairs[Data(tokens[tokens.count - 2].utf8)]?[Data(tokens[tokens.count - 1].utf8)]
        else {
            return nil
        }
        let child = tokens[tokens.count - 1]
        return plainNames.contains(child) ? pair + [child] : pair
    }

    private static func tokens(_ name: String) -> [String] {
        name.components(separatedBy: ".")
            .flatMap { $0.components(separatedBy: "__") }
            .filter { !$0.isEmpty }
    }

    /// `mcp__tools__collaboration_spawn_agent`: the longest declared child
    /// that terminates the name after a whole separator, uniquely.
    private func resolvedBySuffix(_ emitted: String) -> String? {
        // Dictionary order is randomized per process; sort so the longest
        // candidate deterministically leads and the verdict is stable.
        let matches =
            childNames
            .filter {
                emitted.utf8.reversed().starts(with: (Data("_".utf8) + $0.key).reversed())
            }
            .sorted { $0.key.count > $1.key.count }
        guard let best = matches.first else {
            return nil
        }
        return uniqueNamespaceCandidate(best.value)
    }

    private func uniqueNamespaceCandidate(_ candidates: [String]) -> String? {
        guard candidates.count == 1, exact[candidates[0]] != nil else { return nil }
        return candidates[0]
    }

    private static func exactValue<Value>(_ key: String, in values: [String: Value]) -> Value? {
        values.first { $0.key.utf8.elementsEqual(key.utf8) }?.value
    }
}
