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
/// Resolution is purely additive and can never grant permission: every
/// candidate comes from the request's current-turn namespace children, so a
/// resolved name is by construction one the request declared. Historical
/// bindings are deliberately absent — a retired call identity must never
/// become emittable again. When the caller supplies a namespace (a backend
/// that natively restores the pair), only an exact pair match resolves:
/// fuzzy rules would second-guess a backend that already names its tools
/// precisely.
package struct ProviderToolNamespaceResolver: Sendable {
    private let exact: [String: ResponsesToolNamespaces.Binding]
    private let childNames: [String: [String]]
    /// Last namespace segment → child name → the wire names that pair
    /// declares. Nested dictionaries keep the lookup collision-free without
    /// a key struct whose fields Periphery would flag as assign-only.
    private let namespacePairs: [String: [String: [String]]]

    package init(declaredBindings: [String: ResponsesToolNamespaces.Binding]) {
        var childNames: [String: [String]] = [:]
        var namespacePairs: [String: [String: [String]]] = [:]
        for (wireName, binding) in declaredBindings {
            childNames[binding.name, default: []].append(wireName)
            let segments = binding.namespace.split(separator: ".")
            if let lastSegment = segments.last {
                namespacePairs[
                    String(lastSegment),
                    default: [:]
                ][binding.name, default: []].append(wireName)
            }
        }
        self.exact = declaredBindings
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
        if exact[emitted] != nil {
            return emitted
        }
        if let unique = childNames[emitted], unique.count == 1 {
            return unique[0]
        }
        if let unique = resolvedByTokens(emitted) {
            return unique
        }
        return resolvedBySuffix(emitted)
    }

    /// `functions.collaboration.spawn_agent`: split on `__` and `.` and match
    /// the trailing `lastNamespaceSegment + child` couple, uniquely.
    private func resolvedByTokens(_ emitted: String) -> String? {
        let tokens =
            emitted
            .components(separatedBy: ".")
            .flatMap { $0.components(separatedBy: "__") }
            .filter { !$0.isEmpty }
        guard tokens.count >= 2,
            let pair = namespacePairs[tokens[tokens.count - 2]]?[
                tokens[tokens.count - 1]
            ],
            pair.count == 1
        else {
            return nil
        }
        return pair[0]
    }

    /// `mcp__tools__collaboration_spawn_agent`: the longest declared child
    /// that terminates the name after a whole separator, uniquely.
    private func resolvedBySuffix(_ emitted: String) -> String? {
        // Dictionary order is randomized per process; sort so the longest
        // candidate deterministically leads and the verdict is stable.
        let matches =
            childNames
            .filter {
                emitted.hasSuffix("__\($0.key)") || emitted.hasSuffix("_\($0.key)")
            }
            .sorted { $0.key.count > $1.key.count }
        guard let best = matches.first, best.value.count == 1 else {
            return nil
        }
        return best.value[0]
    }
}
