import Foundation

/// A search bridge owns a declaration it inserted, never a client's bare name.
enum ResponsesPrivateSearchBinding {
    static func name(tools: [[String: Any]], input: Any?) -> String {
        let history = input as? [[String: Any]] ?? []
        let names = Set((tools + history).compactMap { $0["name"] as? String })
        if !names.contains("web_search") { return "web_search" }
        let base = "__little_switch_web_search"
        var candidate = base
        var suffix = 2
        while names.contains(candidate) {
            candidate = "\(base)_\(suffix)"
            suffix += 1
        }
        return candidate
    }
}
