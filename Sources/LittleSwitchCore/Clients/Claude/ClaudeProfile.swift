import Foundation
import LittleSwitchCommon
import LittleSwitchSearch

public enum ClaudeProfileIdentity {
    public static let id = "cd35496d-e4c2-49f6-9bfa-69e0b3e22505"
    public static let name = ProductIdentity.displayName
    /// The gateway origin once the TLS leaf is trusted, served to both the
    /// Desktop profile and the Claude Code managed settings.
    /// Desktop's built-in web-search contract only accepts https custom
    /// endpoints, so the https origin rides the TLS side of the listener.
    public static let gatewayBaseURL = "https://127.0.0.1:11436"
    /// The fallback origin written while the leaf is not trusted yet: the
    /// listener speaks both protocols on the same port, so the Desktop
    /// stays fully functional over plain http until trust is granted.
    package static let gatewayHTTPBaseURL = "http://127.0.0.1:11436"
    public static let gatewayAPIKey = ProductIdentity.gatewayAPIKey
}

public struct ClaudeProfilePaths: Equatable, Sendable {
    public let normalConfig: URL
    public let thirdPartyConfig: URL
    public let metadata: URL
    public let profile: URL
    public let backupDirectory: URL
    /// The gateway's own configuration, read (never written) to know whether
    /// the managed web-search entry should join the deployment profile.
    public let littleSwitchConfig: URL

    public var managedFiles: [URL] {
        [normalConfig, thirdPartyConfig, metadata, profile]
    }

    public init(applicationSupport: URL) {
        let normalRoot = applicationSupport.appending(path: "Claude", directoryHint: .isDirectory)
        let thirdPartyRoot = applicationSupport.appending(
            path: "Claude-3p",
            directoryHint: .isDirectory
        )
        let library = thirdPartyRoot.appending(path: "configLibrary", directoryHint: .isDirectory)
        normalConfig = normalRoot.appending(path: "claude_desktop_config.json")
        thirdPartyConfig = thirdPartyRoot.appending(path: "claude_desktop_config.json")
        metadata = library.appending(path: "_meta.json")
        profile = library.appending(path: "\(ClaudeProfileIdentity.id).json")
        let selfRoot = applicationSupport.appending(
            path: ProductIdentity.applicationSupportDirectoryName,
            directoryHint: .isDirectory
        )
        littleSwitchConfig = selfRoot.appending(path: "config.json")
        backupDirectory = selfRoot.appending(path: "Backups", directoryHint: .isDirectory)
            .appending(path: "Claude", directoryHint: .isDirectory)
    }

    public static func live(fileManager: FileManager = .default) throws -> Self {
        guard
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            throw ClaudeProfileManager.Error.applicationSupportUnavailable
        }
        return Self(applicationSupport: applicationSupport)
    }
}

public protocol ClaudeProfileFileStore: Sendable {
    func snapshot(_ url: URL) throws -> Data?
    func readObject(_ url: URL) throws -> [String: Any]
    func writeObject(_ object: [String: Any], to url: URL) throws
    func restore(_ data: Data?, to url: URL) throws
}

public struct DiskClaudeProfileFileStore: ClaudeProfileFileStore {
    public enum Error: Swift.Error, Equatable {
        case invalidJSON(URL)
    }

    public let backupDirectory: URL

    public init(backupDirectory: URL) {
        self.backupDirectory = backupDirectory
    }

    public func snapshot(_ url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    public func readObject(_ url: URL) throws -> [String: Any] {
        guard let data = try snapshot(url) else {
            return [:]
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Error.invalidJSON(url)
        }
        return object
    }

    public func writeObject(_ object: [String: Any], to url: URL) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw Error.invalidJSON(url)
        }
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try AtomicFileWriter.write(
            data,
            to: url,
            backupDirectory: backupDirectory
        )
    }

    public func restore(_ data: Data?, to url: URL) throws {
        guard let data else {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return
        }
        try AtomicFileWriter.write(
            data,
            to: url,
            backupDirectory: backupDirectory
        )
    }
}

public protocol ClaudeProfileManaging: Sendable {
    func activate(autoMode: Bool, tlsEnabled: Bool) throws
    func restore() throws
    func isActive(autoMode: Bool) throws -> Bool
}

public struct ClaudeProfileManager: Sendable {
    public enum Error: Swift.Error, Equatable {
        case applicationSupportUnavailable
        case rollbackFailed
    }

    // The desktop profile document keys settings by their registry name
    // (`allowedPluginMarketplaces`); `marketplaces` is not a recognized
    // profile key and makes Desktop warn at launch.
    // https://claude.com/docs/third-party/claude-desktop/configuration#allowedpluginmarketplaces
    static let defaultMarketplaces: [[String: String]] = [
        ["source": "github", "repo": "anthropics/claude-plugins-official"],
        ["source": "github", "repo": "anthropics/knowledge-work-plugins"],
    ]

    /// The name of the managed `websearch` entry this app owns inside the
    /// deployment profile's `managedMcpServers` array. Desktop stops
    /// offering provider-side search once the entry exists and runs the
    /// search itself against the gateway's `{q}` endpoint.
    static let managedWebSearchServerName = "Web search"

    static func managedWebSearchServer(baseURL: String) -> [String: Any] {
        [
            "name": managedWebSearchServerName,
            "server": "websearch",
            "provider": "custom",
            "customUrl": "\(baseURL)/api/web-search",
            "toolPolicy": ["web_search": "allow"],
        ]
    }

    private struct Snapshot {
        let url: URL
        let data: Data?
    }

    public let paths: ClaudeProfilePaths
    private let fileStore: any ClaudeProfileFileStore

    public init(
        paths: ClaudeProfilePaths,
        fileStore: (any ClaudeProfileFileStore)? = nil
    ) {
        self.paths = paths
        self.fileStore =
            fileStore
            ?? DiskClaudeProfileFileStore(
                backupDirectory: paths.backupDirectory
            )
    }

    public func activate(autoMode: Bool, tlsEnabled: Bool) throws {
        var profile = try fileStore.readObject(paths.profile)
        var metadata = try fileStore.readObject(paths.metadata)
        var thirdParty = try fileStore.readObject(paths.thirdPartyConfig)
        var normal = try fileStore.readObject(paths.normalConfig)

        let inferenceModels = managedInferenceModels()
        configureProfile(
            &profile,
            autoMode: autoMode,
            tlsEnabled: tlsEnabled,
            inferenceModels: inferenceModels
        )
        configureMetadata(&metadata)
        thirdParty["deploymentMode"] = "3p"
        normal["deploymentMode"] = "3p"
        // The entry's https-only contract means it rides the TLS side only.
        configureManagedWebSearch(
            &profile,
            enabled: tlsEnabled && managedWebSearchEnabled()
        )

        try transaction {
            try fileStore.writeObject(profile, to: paths.profile)
            try fileStore.writeObject(metadata, to: paths.metadata)
            try fileStore.writeObject(thirdParty, to: paths.thirdPartyConfig)
            try fileStore.writeObject(normal, to: paths.normalConfig)
        }
    }

    public func restore() throws {
        var normal = try fileStore.readObject(paths.normalConfig)
        var thirdParty = try fileStore.readObject(paths.thirdPartyConfig)
        var metadata = try fileStore.readObject(paths.metadata)
        var profile = try fileStore.readObject(paths.profile)

        normal["deploymentMode"] = "1p"
        thirdParty["deploymentMode"] = "1p"
        restoreMetadata(&metadata)
        restoreProfile(&profile)

        try transaction {
            try fileStore.writeObject(normal, to: paths.normalConfig)
            try fileStore.writeObject(thirdParty, to: paths.thirdPartyConfig)
            try fileStore.writeObject(metadata, to: paths.metadata)
            try fileStore.writeObject(profile, to: paths.profile)
        }
    }

    public func isActive(autoMode: Bool) throws -> Bool {
        let normal = try fileStore.readObject(paths.normalConfig)
        let thirdParty = try fileStore.readObject(paths.thirdPartyConfig)
        let metadata = try fileStore.readObject(paths.metadata)
        let profile = try fileStore.readObject(paths.profile)
        let profileName = profile["deploymentDisplayName"] as? String
        let apiKey = profile["inferenceGatewayApiKey"] as? String
        let hasSupportedIdentity =
            (profileName == ClaudeProfileIdentity.name
                && apiKey == ClaudeProfileIdentity.gatewayAPIKey)
            || (profileName == ProductIdentity.Legacy.ModelSwitch.displayName
                && apiKey == ProductIdentity.Legacy.ModelSwitch.gatewayAPIKey)
            || (profileName == ProductIdentity.Legacy.ModelSwitcher.displayName
                && apiKey == ProductIdentity.Legacy.ModelSwitcher.gatewayAPIKey)
        guard normal["deploymentMode"] as? String == "3p",
            thirdParty["deploymentMode"] as? String == "3p",
            metadata["appliedId"] as? String == ClaudeProfileIdentity.id,
            profile["inferenceProvider"] as? String == "gateway",
            profile["inferenceGatewayBaseUrl"] as? String
                == ClaudeProfileIdentity.gatewayBaseURL
                || profile["inferenceGatewayBaseUrl"] as? String
                    == ClaudeProfileIdentity.gatewayHTTPBaseURL,
            profile["modelDiscoveryEnabled"] as? Bool == true,
            isManagedInferenceModelsActive(
                profile["inferenceModels"], expected: managedInferenceModels()
            ),
            hasSupportedIdentity,
            profile["autoModeEnabled"] as? Bool == autoMode
        else {
            return false
        }
        return true
    }

    private func transaction(_ operation: () throws -> Void) throws {
        let snapshots = try paths.managedFiles.map { url in
            Snapshot(url: url, data: try fileStore.snapshot(url))
        }
        do {
            try operation()
        } catch {
            do {
                for snapshot in snapshots.reversed() {
                    try fileStore.restore(snapshot.data, to: snapshot.url)
                }
            } catch {
                throw Error.rollbackFailed
            }
            throw error
        }
    }

    private func configureProfile(
        _ profile: inout [String: Any],
        autoMode: Bool,
        tlsEnabled: Bool,
        inferenceModels: [[String: Any]]?
    ) {
        profile["inferenceProvider"] = "gateway"
        profile["inferenceGatewayBaseUrl"] =
            tlsEnabled
            ? ClaudeProfileIdentity.gatewayBaseURL
            : ClaudeProfileIdentity.gatewayHTTPBaseURL
        profile["inferenceGatewayApiKey"] = ClaudeProfileIdentity.gatewayAPIKey
        profile["inferenceGatewayAuthScheme"] = "bearer"
        profile["deploymentDisplayName"] = ClaudeProfileIdentity.name
        profile["modelDiscoveryEnabled"] = true
        profile["chatTabEnabled"] = true
        profile["disableDeploymentModeChooser"] = true
        profile["coworkEgressAllowedHosts"] = ["*"]
        profile["disableEssentialTelemetry"] = true
        profile["disableNonessentialTelemetry"] = true
        profile["autoModeEnabled"] = autoMode
        profile["allowedPluginMarketplaces"] = ClaudeProfileManager.defaultMarketplaces
        if let inferenceModels, !inferenceModels.isEmpty {
            profile["inferenceModels"] = inferenceModels
        } else {
            profile.removeValue(forKey: "inferenceModels")
        }
        // Migrate profiles written before the rename: the stale key is what
        // Desktop warned about at every launch.
        profile.removeValue(forKey: "marketplaces")
    }

    private func managedInferenceModels() -> [[String: Any]]? {
        guard let object = try? fileStore.readObject(paths.littleSwitchConfig),
            let data = try? JSONSerialization.data(withJSONObject: object),
            let configuration = try? JSONDecoder().decode(AppConfiguration.self, from: data)
        else {
            return nil
        }
        let choices = ClaudeCodeModelChoice.available(
            providers: configuration.providers,
            mappings: configuration.mappings,
            indicator: configuration.modelIndicator
        )
        return choices.map { choice in
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

    private func isManagedInferenceModelsActive(
        _ actual: Any?,
        expected: [[String: Any]]?
    ) -> Bool {
        guard let expected else {
            return true
        }
        guard let actual,
            JSONSerialization.isValidJSONObject(actual),
            let actualData = try? JSONSerialization.data(
                withJSONObject: actual, options: [.sortedKeys]
            ),
            let expectedData = try? JSONSerialization.data(
                withJSONObject: expected, options: [.sortedKeys]
            )
        else {
            return false
        }
        return actualData == expectedData
    }

    private func configureMetadata(_ metadata: inout [String: Any]) {
        metadata["appliedId"] = ClaudeProfileIdentity.id
        var entries = metadata["entries"] as? [Any] ?? []
        entries.removeAll { entry in
            (entry as? [String: Any])?["id"] as? String == ClaudeProfileIdentity.id
        }
        entries.append([
            "id": ClaudeProfileIdentity.id,
            "name": ClaudeProfileIdentity.name,
        ])
        metadata["entries"] = entries
    }

    private func restoreMetadata(_ metadata: inout [String: Any]) {
        if metadata["appliedId"] as? String == ClaudeProfileIdentity.id {
            metadata.removeValue(forKey: "appliedId")
        }
        guard var entries = metadata["entries"] as? [Any] else {
            return
        }
        entries.removeAll { entry in
            (entry as? [String: Any])?["id"] as? String == ClaudeProfileIdentity.id
        }
        metadata["entries"] = entries
    }

    private func restoreProfile(_ profile: inout [String: Any]) {
        profile["disableDeploymentModeChooser"] = false
        for key in [
            "inferenceProvider",
            "inferenceGatewayBaseUrl",
            "inferenceGatewayApiKey",
            "inferenceGatewayAuthScheme",
            "deploymentDisplayName",
            "inferenceModels",
            "modelDiscoveryEnabled",
            "coworkEgressAllowedHosts",
            "autoModeEnabled",
            "allowedPluginMarketplaces",
            "marketplaces",
            "disableEssentialTelemetry",
            "disableNonessentialTelemetry",
        ] {
            profile.removeValue(forKey: key)
        }
        restoreManagedWebSearch(&profile)
    }

    /// Replaces this app's entry in the profile's `managedMcpServers`
    /// array — foreign entries (the user's, or an MDM profile's) survive
    /// untouched, and the key disappears again when nothing is left to
    /// serve. With search disabled the entry is simply not written: the
    /// Desktop falls back to provider-side search.
    private func configureManagedWebSearch(
        _ profile: inout [String: Any],
        enabled: Bool
    ) {
        var servers = (profile["managedMcpServers"] as? [Any] ?? [])
            .filter { !isOwnedManagedWebSearchServer($0) }
        if enabled {
            servers.append(
                ClaudeProfileManager.managedWebSearchServer(
                    baseURL: ClaudeProfileIdentity.gatewayBaseURL
                )
            )
        }
        if servers.isEmpty {
            profile.removeValue(forKey: "managedMcpServers")
        } else {
            profile["managedMcpServers"] = servers
        }
    }

    private func restoreManagedWebSearch(_ profile: inout [String: Any]) {
        guard var servers = profile["managedMcpServers"] as? [Any] else {
            return
        }
        servers.removeAll { isOwnedManagedWebSearchServer($0) }
        if servers.isEmpty {
            profile.removeValue(forKey: "managedMcpServers")
        } else {
            profile["managedMcpServers"] = servers
        }
    }

    private func isOwnedManagedWebSearchServer(_ entry: Any) -> Bool {
        (entry as? [String: Any])?["name"] as? String
            == ClaudeProfileManager.managedWebSearchServerName
    }

    /// Reads the gateway's own configuration for the entry decision. A
    /// missing or unreadable file means defaults, and the default provider
    /// is enabled; only an explicit `disabled` suppresses the entry.
    private func managedWebSearchEnabled() -> Bool {
        guard let object = try? fileStore.readObject(paths.littleSwitchConfig),
            let webSearch = object["webSearch"] as? [String: Any]
        else {
            return true
        }
        return (webSearch["provider"] as? String) != WebSearchProvider.disabled.rawValue
    }
}

extension ClaudeProfileManager: ClaudeProfileManaging {}
