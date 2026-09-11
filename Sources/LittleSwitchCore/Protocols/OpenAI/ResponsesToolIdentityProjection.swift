import Foundation

/// Restores the `name` + `namespace` pair Codex resolves against when a
/// flattened provider call matches a request binding. Incoming frames
/// keep the wire name; only emitted item JSON is rewritten.
func restoredResponsesToolItem(
    _ item: [String: Any],
    binding: ResponsesToolNamespaces.Binding?
) -> [String: Any] {
    guard let binding else {
        return item
    }
    var restored = item
    restored["name"] = binding.name
    restored["namespace"] = binding.namespace
    return restored
}
