import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Provider tool namespace resolver")
struct ProviderToolNamespaceResolverTests {
    /// The production declarations: Codex's collaboration namespace plus an
    /// MCP-style namespace whose children collide with the flat helpers.
    private func resolver(
        namespaces: [(name: String, children: [String])] = [
            ("collaboration", ["spawn_agent", "list_agents", "send_message"]),
            ("mcp.tools", ["call_tool"]),
        ]
    ) -> ProviderToolNamespaceResolver {
        var bindings: [String: ResponsesToolNamespaces.Binding] = [:]
        for namespace in namespaces {
            for child in namespace.children {
                bindings[ResponsesToolNamespaces.flattenedName(namespace: namespace.name, name: child)] =
                    ResponsesToolNamespaces.Binding(namespace: namespace.name, name: child)
            }
        }
        return ProviderToolNamespaceResolver(declaredBindings: bindings)
    }

    @Test("The exact flattened wire name resolves to itself")
    func exactWireName() {
        let resolved = resolver().wireName(for: "collaboration__spawn_agent", namespace: nil)
        #expect(resolved == "collaboration__spawn_agent")
    }

    @Test("A bare child name resolves when unique across namespaces")
    func bareChildName() {
        let resolved = resolver().wireName(for: "spawn_agent", namespace: nil)
        #expect(resolved == "collaboration__spawn_agent")
        #expect(resolver().wireName(for: "list_agents", namespace: nil) == "collaboration__list_agents")
    }

    @Test("A bare child name shared by two namespaces stays unresolved")
    func ambiguousBareChildName() {
        let resolved = resolver(
            namespaces: [
                ("one", ["ping"]),
                ("two", ["ping"]),
            ]
        ).wireName(for: "ping", namespace: nil)
        #expect(resolved == nil)
    }

    @Test(
        "Ambiguous bare children cannot fall through to token or shorter suffix recovery",
        arguments: ["a_b", "a.b", "a__b"])
    func ambiguousChildStopsRecovery(child: String) {
        let bindings: [String: ResponsesToolNamespaces.Binding] = [
            "x__\(child)": .init(namespace: "x", name: child),
            "y__\(child)": .init(namespace: "y", name: child),
            "outer.a__b": .init(namespace: "outer.a", name: "b"),
        ]
        let resolver = ProviderToolNamespaceResolver(declaredBindings: bindings)
        #expect(resolver.wireName(for: child, namespace: nil) == nil)
        #expect(resolver.restoredBinding(for: child, bindings: bindings) == nil)
        #expect(resolver.wireName(for: child, namespace: "x") == "x__\(child)")
        #expect(resolver.wireName(for: "x__\(child)", namespace: nil) == "x__\(child)")
    }

    @Test("A dotted path resolves by its trailing namespace segment and child")
    func dottedNearMiss() {
        let resolved = resolver().wireName(for: "functions.collaboration.spawn_agent", namespace: nil)
        #expect(resolved == "collaboration__spawn_agent")
    }

    @Test("A double-underscore path resolves by its trailing namespace segment and child")
    func underscorePathNearMiss() {
        let resolved = resolver().wireName(for: "gateway__mcp.tools__call_tool", namespace: nil)
        #expect(resolved == "mcp.tools__call_tool")
    }

    @Test("A prefixed flat name resolves by its longest declared child suffix")
    func prefixedNearMiss() {
        let resolved = resolver().wireName(for: "mcp__tools__collaboration_spawn_agent", namespace: nil)
        #expect(resolved == "collaboration__spawn_agent")
    }

    @Test("The longest declared child suffix wins over its own prefix")
    func longestSuffixWins() {
        let resolved = resolver(
            namespaces: [("collaboration", ["agent", "spawn_agent"])]
        ).wireName(for: "mcp__tools__collaboration_spawn_agent", namespace: nil)
        #expect(resolved == "collaboration__spawn_agent")
    }

    @Test("An ambiguous prefixed name stays unresolved")
    func ambiguousPrefix() {
        let resolved = resolver(
            namespaces: [
                ("collaboration", ["spawn_agent"]),
                ("teamwork", ["spawn_agent"]),
            ]
        ).wireName(for: "mcp__tools__collaboration_spawn_agent", namespace: nil)
        #expect(resolved == nil)
    }

    @Test("A trailing token that is not a whole declared child never strips greedily")
    func doesNotStripUnderscoreTokens() {
        let resolved = resolver(
            namespaces: [("sandbox", ["js"])]
        ).wireName(for: "js_reset", namespace: nil)
        #expect(resolved == nil)
    }

    @Test("An unknown name stays unresolved")
    func unknownName() {
        #expect(resolver().wireName(for: "totally_unknown", namespace: nil) == nil)
        #expect(resolver().wireName(for: "collaboration__unknown", namespace: nil) == nil)
        #expect(resolver().wireName(for: "", namespace: nil) == nil)
    }

    @Test("A supplied namespace resolves only the exact pair, never fuzzed")
    func suppliedNamespaceIsPairOnly() throws {
        let resolved = resolver()
        #expect(resolved.wireName(for: "spawn_agent", namespace: "collaboration") == "collaboration__spawn_agent")
        // A near-miss spelling with a namespace must not recover: the backend
        // named its tools precisely and the pair simply is not declared.
        #expect(resolved.wireName(for: "functions.collaboration.spawn_agent", namespace: "collaboration") == nil)
        #expect(resolved.wireName(for: "spawn_agent", namespace: "collaboration ") == nil)
        #expect(resolved.wireName(for: "spawn_agent", namespace: "other") == nil)
        // A namespace whose segments share the child across namespaces.
        let ambiguous = resolver(
            namespaces: [
                ("one.deps", ["ping"]),
                ("two.deps", ["ping"]),
            ]
        )
        #expect(ambiguous.wireName(for: "ping", namespace: "one.deps") == "one.deps__ping")
        #expect(ambiguous.wireName(for: "ping", namespace: "three.deps") == nil)
    }

    @Test("History-only bindings are not part of the resolution set")
    func historyBindingsNeverResolve() {
        let resolver = ProviderToolNamespaceResolver(
            declaredBindings: ["collaboration__spawn_agent": .init(namespace: "collaboration", name: "spawn_agent")]
        )
        // The exact retired wire name resolves when the request still declares
        // it; a retired name absent from the declarations never does.
        #expect(resolver.wireName(for: "gone__retired", namespace: nil) == nil)
        #expect(resolver.wireName(for: "retired", namespace: nil) == nil)
    }

    @Test("Empty declarations resolve nothing")
    func emptyDeclarations() {
        let resolver = ProviderToolNamespaceResolver(declaredBindings: [:])
        #expect(resolver.wireName(for: "spawn_agent", namespace: nil) == nil)
        #expect(resolver.wireName(for: "spawn_agent", namespace: "collaboration") == nil)
    }

    @Test("A child name that equals a declared wire name prefers the exact match")
    func childNamedLikeWireName() {
        let resolver = resolver(
            namespaces: [
                ("collaboration", ["spawn_agent"]),
                ("flat", ["collaboration__spawn_agent"]),
            ]
        )
        // The bare name is itself a declared wire name for another tool:
        // exact wins before any child lookup.
        #expect(resolver.wireName(for: "collaboration__spawn_agent", namespace: nil) == "collaboration__spawn_agent")
        // And the flat namespace's own child remains reachable.
        #expect(resolver.wireName(for: "flat__collaboration__spawn_agent", namespace: nil) != nil)
    }

    @Test("Plain declarations preserve exact names and veto competing token and suffix candidates")
    func plainDeclarationCandidates() {
        let bindings: [String: ResponsesToolNamespaces.Binding] = [
            "workspace__read_file": .init(namespace: "workspace", name: "read_file")
        ]
        let resolver = ProviderToolNamespaceResolver(
            declaredBindings: bindings,
            nameCatalog: ProviderToolNameCatalog(declared: [
                "read_file", "workspace__read_file", "functions.workspace.read_file", "workspace_read_file",
                "other.ping",
            ])
        )
        #expect(resolver.wireName(for: "read_file", namespace: nil) == "read_file")
        #expect(resolver.restoredBinding(for: "read_file", bindings: bindings) == nil)
        #expect(
            resolver.wireName(for: "functions.workspace.read_file", namespace: nil) == "functions.workspace.read_file")
        #expect(resolver.restoredBinding(for: "functions.workspace.read_file", bindings: bindings) == nil)
        #expect(resolver.wireName(for: "prefix.functions.workspace.read_file", namespace: nil) == nil)
        #expect(resolver.wireName(for: "prefix__read_file", namespace: nil) == nil)
        #expect(resolver.wireName(for: "mcp__tools__workspace_read_file", namespace: nil) == nil)
        #expect(resolver.wireName(for: "prefix.other.ping", namespace: nil) == nil)
        #expect(resolver.restoredBinding(for: "read_file", namespace: "other", bindings: bindings) == nil)
    }

    @Test("Retired exact names restore their identity without resolving as current declarations")
    func retiredNamesOnlyRestore() {
        let declared: [String: ResponsesToolNamespaces.Binding] = [
            "workspace__read_file": .init(namespace: "workspace", name: "read_file")
        ]
        let retired = ResponsesToolNamespaces.Binding(namespace: "gone", name: "read_file")
        var bindings = declared
        bindings["gone__read_file"] = retired
        let resolver = ProviderToolNamespaceResolver(
            declaredBindings: declared,
            nameCatalog: ProviderToolNameCatalog(historical: ["gone__read_file", "read_file"])
        )
        #expect(resolver.wireName(for: "gone__read_file", namespace: nil) == nil)
        #expect(resolver.wireName(for: "read_file", namespace: nil) == nil)
        #expect(resolver.restoredBinding(for: "gone__read_file", bindings: bindings) == retired)
        #expect(resolver.restoredBinding(for: "read_file", bindings: bindings) == nil)
        #expect(resolver.restoredBinding(for: "read_file", namespace: "gone", bindings: bindings) == retired)
    }

    @Test("An ambiguous qualified name cannot fall through to suffix recovery")
    func ambiguousTokensDoNotFallThrough() {
        let resolver = ProviderToolNamespaceResolver(
            declaredBindings: ["workspace__read_file": .init(namespace: "workspace", name: "read_file")],
            nameCatalog: ProviderToolNameCatalog(declared: ["functions.workspace.read_file"])
        )
        #expect(resolver.wireName(for: "prefix__workspace__read_file", namespace: nil) == nil)
    }
}
