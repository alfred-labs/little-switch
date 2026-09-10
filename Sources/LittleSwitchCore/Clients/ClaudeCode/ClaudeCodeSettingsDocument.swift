import Foundation

public enum ClaudeCodeSettingsDocument {
    public enum Error: Swift.Error, Equatable {
        case invalidUTF8
        case invalidJSON
        case nonObjectRoot
        case nonObjectEnvironment
    }

    public static func activating(
        _ current: Data?,
        managed: ClaudeCodeManagedSettings
    ) throws -> Data {
        var root = try object(from: current)
        var environment = try environment(from: root)
        root["model"] = managed.model
        for (key, value) in managed.environment {
            environment[key] = value
        }
        root["env"] = environment
        return try encode(root)
    }

    public static func restoring(
        current: Data?,
        original: Data?,
        managed: ClaudeCodeManagedSettings
    ) throws -> Data? {
        guard let current else {
            return nil
        }
        var currentRoot = try object(from: current)
        let originalRoot = try object(from: original)

        if currentRoot["model"] as? String == managed.model {
            restoreValue(
                key: "model",
                original: originalRoot,
                destination: &currentRoot
            )
        }

        var currentEnvironment = try environment(from: currentRoot)
        let originalEnvironment = try environment(from: originalRoot)
        for (key, value) in managed.environment
        where currentEnvironment[key] as? String == value {
            restoreValue(
                key: key,
                original: originalEnvironment,
                destination: &currentEnvironment
            )
        }
        if originalRoot["env"] == nil, currentEnvironment.isEmpty {
            currentRoot.removeValue(forKey: "env")
        } else {
            currentRoot["env"] = currentEnvironment
        }

        guard original != nil || !currentRoot.isEmpty else {
            return nil
        }
        return try encode(currentRoot)
    }

    public static func isManaged(
        _ current: Data?,
        managed: ClaudeCodeManagedSettings
    ) throws -> Bool {
        guard let current else {
            return false
        }
        let root = try object(from: current)
        guard root["model"] as? String == managed.model,
            let environment = root["env"] as? [String: Any]
        else {
            return false
        }
        return managed.environment.allSatisfy { key, value in
            environment[key] as? String == value
        }
    }

    package static func semanticallyMatches(_ left: Data?, _ right: Data?) throws -> Bool {
        switch (left, right) {
        case (nil, nil):
            true
        case (nil, _), (_, nil):
            false
        case (.some, .some):
            try encode(object(from: left)) == encode(object(from: right))
        }
    }

    private static func object(from data: Data?) throws -> [String: Any] {
        guard let data else {
            return [:]
        }
        guard String(data: data, encoding: .utf8) != nil else {
            throw Error.invalidUTF8
        }
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw Error.invalidJSON
        }
        guard let object = value as? [String: Any] else {
            throw Error.nonObjectRoot
        }
        return object
    }

    private static func environment(
        from root: [String: Any]
    ) throws -> [String: Any] {
        guard let value = root["env"] else {
            return [:]
        }
        guard let environment = value as? [String: Any] else {
            throw Error.nonObjectEnvironment
        }
        return environment
    }

    private static func restoreValue(
        key: String,
        original: [String: Any],
        destination: inout [String: Any]
    ) {
        if let value = original[key] {
            destination[key] = value
        } else {
            destination.removeValue(forKey: key)
        }
    }

    private static func encode(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }
}
