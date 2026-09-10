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
        package let bindings: [String: Binding]
    }

    package static func flatten(
        tools: [[String: Any]],
        history: [[String: Any]] = []
    ) -> Flattened {
        var flattened: [[String: Any]] = []
        var bindings: [String: Binding] = [:]
        var used = Set(
            tools.compactMap { tool -> String? in
                guard tool["type"] as? String == "function" else {
                    return nil
                }
                return tool["name"] as? String
            }
        )
        for item in history {
            guard item["type"] as? String == "function_call", nonemptyName(item["namespace"]) == nil else { continue }
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
                    subTool["type"] as? String == "function",
                    let name = nonemptyName(subTool["name"])
                else {
                    continue
                }
                let flatName = flattenedName(namespace: namespace, name: name)
                // A colliding flat name must stay callable: disambiguate with a
                // deterministic fingerprint instead of dropping the sub-tool.
                let wireName =
                    used.contains(flatName)
                    ? disambiguatedName(joined: namespace + separator + name, taken: used)
                    : flatName
                used.insert(wireName)
                var replacement = subTool
                replacement["name"] = wireName
                flattened.append(replacement)
                bindings[wireName] = Binding(namespace: namespace, name: name)
            }
        }
        // Retired tools remain in the transcript. Keep their identity without
        // making the tool callable again by adding a declaration.
        for item in history where item["type"] as? String == "function_call" {
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
        return Flattened(tools: flattened, bindings: bindings)
    }

    package static func flattenedName(namespace: String, name: String) -> String {
        let joined = namespace + separator + name
        guard joined.count > maximumNameLength else {
            return joined
        }
        return shortenedName(joined)
    }

    private static func shortenedName(_ joined: String) -> String {
        let digest = SHA256.hash(data: Data(joined.utf8))
        let fingerprint = digest.prefix(6).map { String(format: "%02x", $0) }.joined()
        let prefixLength = maximumNameLength - fingerprint.count - separator.count
        let prefix = String(joined.prefix(prefixLength))
        return prefix + separator + fingerprint
    }

    private static func disambiguatedName(joined: String, taken: Set<String>) -> String {
        var salt = 1
        var candidate = shortenedName("\(joined)#\(salt)")
        while taken.contains(candidate) {
            salt += 1
            candidate = shortenedName("\(joined)#\(salt)")
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
