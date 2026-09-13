import Foundation
import LittleSwitchWire

/// Restores the `name` + `namespace` pair Codex resolves against when a
/// flattened provider call matches a request binding. Incoming frames
/// keep the wire name; only emitted item JSON is rewritten.
func restoredResponsesToolItem(
    _ item: OpenAIResponsesOutputItem, binding: ResponsesToolNamespaces.Binding?
) -> OpenAIResponsesOutputItem {
    guard let binding else { return item }
    let restored: OpenAIResponsesOutputItem
    switch item {
    case .functionCall(var call):
        call.name = binding.name
        call.namespace = .value(binding.namespace)
        restored = .functionCall(call)
    case .customToolCall(var call):
        call.name = binding.name
        call.namespace = .value(binding.namespace)
        restored = .customToolCall(call)
    default: return item
    }
    return restored
}
