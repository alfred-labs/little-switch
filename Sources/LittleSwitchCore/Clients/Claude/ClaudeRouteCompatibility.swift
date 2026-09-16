import LittleSwitchCommon

/// Retired public IDs stay addressable by existing sessions, while persisted
/// mappings and new catalogs use the current route identity.
package enum ClaudeRouteCompatibility {
    package static func canonicalID(_ identifier: String) -> String {
        if identifier == "claude-fable-5" {
            return "claude-fable-5-1"
        }
        return ClaudeRoute.all.first { $0.family == identifier }?.id ?? identifier
    }

    package static func migrate(_ mappings: [String: ModelMapping]) -> [String: ModelMapping] {
        var result = mappings
        if let legacy = result.removeValue(forKey: "claude-fable-5"), result["claude-fable-5-1"] == nil {
            result["claude-fable-5-1"] = legacy
        }
        return result
    }
}
