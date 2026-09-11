import CryptoKit
import Foundation

/// Flattens the namespaced tools Codex exposes into plain function tools.
///
/// Codex groups collaboration and MCP tools into `{"type": "namespace"}` specs
/// and expects a matching `namespace` field back on the call. That shape is
/// specific to the Responses API: providers that only implement plain function
/// calling ignore it, so the tools are invisible to the model. Flattening the
/// namespace into `namespace__tool` makes them callable, and the returned
/// bindings restore the pair Codex resolves against.
package enum ResponsesToolNamespaces {
    package static let separator = "__"
    package static let maximumNameLength = 64

    package struct Binding: Equatable, Hashable, Sendable {
        package let namespace: String
        package let name: String

        package init(namespace: String, name: String) {
            self.namespace = namespace
            self.name = name
        }
    }

    package struct Flattened {
        package let tools: [[String: Any]]
        /// Every wire name this request can restore, including names only
        /// replayed from retired history calls.
        package let bindings: [String: Binding]
        /// The bindings the request's own namespace declarations created.
        /// This is the set an emitted call may be resolved against: history
        /// bindings restore identity but must never grant permission.
        package let declaredBindings: [String: Binding]

        package init(
            tools: [[String: Any]],
            bindings: [String: Binding],
            declaredBindings: [String: Binding]
        ) {
            self.tools = tools
            self.bindings = bindings
            self.declaredBindings = declaredBindings
        }
    }

    package static func flatten(
        tools: [[String: Any]],
        history: [[String: Any]] = [],
        inheritedBindings: [String: Binding] = [:],
        inheritedDeclaredBindings: [String: Binding] = [:]
    ) -> Flattened {
        var flattened: [[String: Any]] = []
        var declaredBindings = inheritedDeclaredBindings
        let declaredFlatNames = Set(
            tools.compactMap { tool -> String? in
                guard ["function", "custom"].contains(tool["type"] as? String ?? "") else {
                    return nil
                }
                return tool["name"] as? String
            }
        )
        // An inherited active declaration is already flattened. A retired
        // alias cannot occupy a real plain declaration's current identity;
        // replayed namespace history receives a fresh noncolliding alias.
        var bindings = inheritedBindings.filter {
            inheritedDeclaredBindings[$0.key] != nil || !declaredFlatNames.contains($0.key)
        }
        var used = declaredFlatNames
        // Internal turns may already declare a collision-safe wire alias.
        // Reserve it before allocating any current or historical identity.
        used.formUnion(inheritedBindings.keys)
        used.formUnion(inheritedDeclaredBindings.keys)
        for item in history {
            guard ["function_call", "custom_tool_call"].contains(item["type"] as? String ?? ""),
                nonemptyName(item["namespace"]) == nil
            else { continue }
            if let name = nonemptyName(item["name"]) {
                used.insert(name)
            }
        }

        for tool in tools {
            guard tool["type"] as? String == "namespace" else {
                flattened.append(tool)
                continue
            }
            guard
                let namespace = nonemptyName(tool["name"]),
                let subTools = tool["tools"] as? [Any]
            else {
                continue
            }
            for entry in subTools {
                guard
                    let subTool = entry as? [String: Any],
                    ["function", "custom"].contains(subTool["type"] as? String ?? ""),
                    let name = nonemptyName(subTool["name"])
                else {
                    continue
                }
                let binding = Binding(namespace: namespace, name: name)
                let flatName = flattenedName(namespace: namespace, name: name)
                // A colliding flat name must stay callable: disambiguate with a
                // deterministic fingerprint instead of dropping the sub-tool.
                let wireName =
                    bindings.first { $0.value == binding }?.key
                    ?? (used.contains(flatName)
                        ? disambiguatedName(joined: namespace + separator + name, taken: used)
                        : flatName)
                used.insert(wireName)
                var replacement = subTool
                replacement["name"] = wireName
                replacement["description"] = flattenedDescription(
                    wireName: wireName,
                    namespace: namespace,
                    namespaceDescription: nonemptyName(tool["description"]),
                    subToolDescription: subTool["description"] as? String
                )
                flattened.append(replacement)
                bindings[wireName] = binding
                declaredBindings[wireName] = binding
            }
        }
        // Retired tools remain in the transcript. Keep their identity without
        // making the tool callable again by adding a declaration.
        for item in history where ["function_call", "custom_tool_call"].contains(item["type"] as? String ?? "") {
            guard let namespace = nonemptyName(item["namespace"]),
                let name = nonemptyName(item["name"])
            else { continue }
            let binding = Binding(namespace: namespace, name: name)
            guard !bindings.values.contains(binding) else { continue }
            let flatName = flattenedName(namespace: namespace, name: name)
            let wireName =
                used.contains(flatName)
                ? disambiguatedName(joined: namespace + separator + name, taken: used) : flatName
            used.insert(wireName)
            bindings[wireName] = binding
        }
        return Flattened(
            tools: flattened,
            bindings: bindings,
            declaredBindings: declaredBindings
        )
    }

    /// A flattened name is the only spelling the provider received, yet
    /// backends routinely emit a near-miss. The description carries the exact
    /// wire name plus the namespace context so the model can copy the name
    /// verbatim and knows which group the tool belongs to.
    private static func flattenedDescription(
        wireName: String,
        namespace: String,
        namespaceDescription: String?,
        subToolDescription: String?
    ) -> String {
        var parts = ["Call this tool by its exact name \"\(wireName)\"."]
        var context = "[\(namespace)]"
        if let namespaceDescription {
            context += " \(namespaceDescription)"
        }
        parts.append(context)
        if let subToolDescription, !subToolDescription.isEmpty {
            parts.append(subToolDescription)
        }
        return parts.joined(separator: " ")
    }

    package static func flattenedName(namespace: String, name: String) -> String {
        let joined = namespace + separator + name
        guard joined.count > maximumNameLength else {
            return joined
        }
        return shortenedName(joined, fingerprintSource: joined)
    }

    private static func shortenedName(_ joined: String, fingerprintSource: String) -> String {
        let digest = SHA256.hash(data: Data(fingerprintSource.utf8))
        let fingerprint = digest.prefix(6).map { String(format: "%02x", $0) }.joined()
        let prefixLength = maximumNameLength - fingerprint.count - separator.count
        let prefix = String(joined.prefix(prefixLength))
        return prefix + separator + fingerprint
    }

    private static func disambiguatedName(joined: String, taken: Set<String>) -> String {
        var salt = 1
        // The salt changes the fingerprint, never the visible tool name.
        var candidate = shortenedName(joined, fingerprintSource: "\(joined)#\(salt)")
        while taken.contains(candidate) {
            salt += 1
            candidate = shortenedName(joined, fingerprintSource: "\(joined)#\(salt)")
        }
        return candidate
    }

    /// The wire name history replay should use for a restored pair: the
    /// request's own binding when flattening disambiguated it, otherwise the
    /// plain flattened name.
    package static func replayName(
        bindings: [String: Binding],
        namespace: String,
        name: String
    ) -> String {
        let target = Binding(namespace: namespace, name: name)
        if let entry = bindings.first(where: { $0.value == target }) {
            return entry.key
        }
        return flattenedName(namespace: namespace, name: name)
    }

    private static func nonemptyName(_ value: Any?) -> String? {
        guard let name = value as? String, !name.isEmpty else {
            return nil
        }
        return name
    }
}
