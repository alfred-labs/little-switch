import Foundation
import LittleSwitchCommon

/// The profile fields owned by catalog publication, shared with activation.
struct ClaudeProfileCatalog {
    private static let ownedKeys = ["modelDiscoveryEnabled", "inferenceModels"]
    private let fields: [String: Any]

    init(choices: [ClaudeCodeModelChoice]) {
        var fields: [String: Any] = ["modelDiscoveryEnabled": true]
        if !choices.isEmpty {
            fields["inferenceModels"] = choices.map(Self.model)
        }
        self.fields = fields
    }

    func matches(_ profile: [String: Any]) throws -> Bool {
        let current = profile.filter { Self.ownedKeys.contains($0.key) }
        return try JSONSerialization.data(withJSONObject: current, options: [.sortedKeys])
            == JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    }

    func apply(to profile: inout [String: Any]) {
        for key in Self.ownedKeys {
            profile[key] = fields[key]
        }
    }

    private static func model(_ choice: ClaudeCodeModelChoice) -> [String: Any] {
        var model: [String: Any] = [
            "name": choice.route.id,
            "labelOverride": choice.baseLabel,
            "anthropicFamilyTier": choice.route.family,
            "isFamilyDefault": choice.route.isFamilyDefault,
        ]
        if choice.contextMode == .extended1M {
            model["supports1m"] = true
        }
        if choice.route.offersMaxEffort {
            model["maxEffort"] = "max"
        }
        return model
    }
}
