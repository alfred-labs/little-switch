import Foundation
import LittleSwitchCommon

public enum OpenCodeSettingsDocument {
    public enum Error: Swift.Error, Equatable {
        case invalidUTF8
        case invalidJSON
        case nonObjectRoot
        case nonObjectProvider
        case nonObjectMCP
    }

    public static func activating(
        _ current: Data?,
        managed: OpenCodeManagedSettings
    ) throws -> Data {
        var root = try object(from: current)
        var providers = try provider(from: root)
        root["model"] = managed.model
        providers[OpenCodeManagedSettings.providerID] = managedProviderObject(managed)
        root["provider"] = providers
        if let mcp = managed.mcp {
            var servers = try mcpServers(from: root)
            servers[mcp.name] = managedMCPObject(mcp)
            root["mcp"] = servers
        }
        return try encode(root)
    }

    public static func restoring(
        current: Data?,
        original: Data?,
        managed: OpenCodeManagedSettings
    ) throws -> Data? {
        guard let current else {
            return nil
        }
        var currentRoot = try object(from: current)
        let originalRoot = try object(from: original)

        if currentRoot["model"] as? String == managed.model {
            restoreValue(key: "model", original: originalRoot, destination: &currentRoot)
        }

        var currentProviders = try provider(from: currentRoot)
        let originalProviders = try provider(from: originalRoot)
        let managedProvider = managedProviderObject(managed)
        if jsonEqual(
            currentProviders[OpenCodeManagedSettings.providerID],
            managedProvider
        ) {
            restoreValue(
                key: OpenCodeManagedSettings.providerID,
                original: originalProviders,
                destination: &currentProviders
            )
        }
        if originalRoot["provider"] == nil, currentProviders.isEmpty {
            currentRoot.removeValue(forKey: "provider")
        } else {
            currentRoot["provider"] = currentProviders
        }

        if let mcp = managed.mcp {
            try restoreMCP(current: &currentRoot, original: originalRoot, managed: mcp)
        }

        guard original != nil || !currentRoot.isEmpty else {
            return nil
        }
        return try encode(currentRoot)
    }

    public static func isManaged(
        _ current: Data?,
        managed: OpenCodeManagedSettings
    ) throws -> Bool {
        guard let current else {
            return false
        }
        let root = try object(from: current)
        guard root["model"] as? String == managed.model else {
            return false
        }
        let providers = try provider(from: root)
        guard
            jsonEqual(
                providers[OpenCodeManagedSettings.providerID],
                managedProviderObject(managed)
            )
        else {
            return false
        }
        guard let mcp = managed.mcp else {
            return true
        }
        let servers = try mcpServers(from: root)
        return jsonEqual(servers[mcp.name], managedMCPObject(mcp))
    }

    static func mcpRecoveryBaseline(original: Data?, current: Data?) throws -> Data? {
        var originalRoot = try object(from: original)
        let currentRoot = try object(from: current)
        guard !jsonEqual(originalRoot["mcp"], currentRoot["mcp"]) else {
            return original
        }
        restoreValue(key: "mcp", original: currentRoot, destination: &originalRoot)
        return try encode(originalRoot)
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

    private static func provider(from root: [String: Any]) throws -> [String: Any] {
        guard let value = root["provider"] else {
            return [:]
        }
        guard let provider = value as? [String: Any] else {
            throw Error.nonObjectProvider
        }
        return provider
    }

    private static func managedProviderObject(
        _ managed: OpenCodeManagedSettings
    ) -> [String: Any] {
        let models = managed.provider.models.mapValues { model in
            var object: [String: Any] = ["name": model.name]
            if let modalities = model.modalities {
                object["modalities"] = ["input": modalities.input, "output": modalities.output]
            }
            if let limit = model.limit {
                var limitObject: [String: Any] = ["output": limit.output]
                if let context = limit.context {
                    limitObject["context"] = context
                }
                object["limit"] = limitObject
            }
            return object
        }
        return [
            "npm": managed.provider.npm,
            "name": managed.provider.name,
            "options": [
                "baseURL": managed.provider.options.baseURL,
                "apiKey": managed.provider.options.apiKey,
            ],
            "models": models,
        ]
    }

    private static func mcpServers(from root: [String: Any]) throws -> [String: Any] {
        guard let value = root["mcp"] else {
            return [:]
        }
        guard let servers = value as? [String: Any] else {
            throw Error.nonObjectMCP
        }
        return servers
    }

    private static func managedMCPObject(_ server: OpenCodeManagedMCPServer) -> [String: Any] {
        [
            "type": server.type,
            "url": server.url,
            "enabled": server.enabled,
            "oauth": server.oauth,
            "timeout": server.timeout,
        ]
    }

    private static func restoreMCP(
        current: inout [String: Any],
        original: [String: Any],
        managed: OpenCodeManagedMCPServer
    ) throws {
        guard current["mcp"] != nil else {
            return
        }
        var servers = try mcpServers(from: current)
        let originalServers = try mcpServers(from: original)
        if jsonEqual(servers[managed.name], managedMCPObject(managed)) {
            restoreValue(
                key: managed.name,
                original: originalServers,
                destination: &servers
            )
        }
        if original["mcp"] == nil, servers.isEmpty {
            current.removeValue(forKey: "mcp")
        } else {
            current["mcp"] = servers
        }
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

    private static func jsonEqual(_ left: Any?, _ right: Any?) -> Bool {
        guard let left, let right else {
            return left == nil && right == nil
        }
        let leftData = try? JSONSerialization.data(
            withJSONObject: ["value": left],
            options: [.sortedKeys]
        )
        let rightData = try? JSONSerialization.data(
            withJSONObject: ["value": right],
            options: [.sortedKeys]
        )
        return leftData == rightData
    }

    private static func encode(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }
}
