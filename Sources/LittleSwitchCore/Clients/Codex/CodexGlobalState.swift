import Foundation

public enum CodexGlobalState {
    public static let persistedAtomStateKey = "electron-persisted-atom-state"
    public static let enabledReasoningEffortsKey = "enabled-reasoning-efforts"
    public static let reasoningEffortsIncludingMaximum = [
        "low", "medium", "high", "xhigh", "max", "ultra",
    ]

    public static func enablingMaximumReasoningEffort(in data: Data?) throws -> Data? {
        guard let data else {
            let atoms: [String: Any] = [
                enabledReasoningEffortsKey: reasoningEffortsIncludingMaximum
            ]
            return try serialize([persistedAtomStateKey: atoms])
        }
        guard var root = parse(data) else {
            return nil
        }
        var atoms: [String: Any]
        if let section = root[persistedAtomStateKey] {
            guard let existingAtoms = section as? [String: Any] else {
                return nil
            }
            atoms = existingAtoms
        } else {
            atoms = [:]
        }
        if let existing = atoms[enabledReasoningEffortsKey] {
            guard let efforts = existing as? [String] else {
                return nil
            }
            guard !efforts.contains("max") else {
                return nil
            }
            atoms[enabledReasoningEffortsKey] = efforts + ["max"]
        } else {
            atoms[enabledReasoningEffortsKey] = reasoningEffortsIncludingMaximum
        }
        root[persistedAtomStateKey] = atoms
        return try serialize(root)
    }

    private static func parse(_ data: Data) -> [String: Any]? {
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    private static func serialize(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }
}
