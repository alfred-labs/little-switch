import Darwin
import Foundation
import LittleSwitchSearch

public struct AppConfiguration: Codable, Equatable, Sendable {
    public var version: Int
    public var providers: [Provider]
    public var mappings: [String: ModelMapping]
    public var autoMode: Bool
    public var connected: Bool
    public var claudeCode: ClaudeCodeConfiguration
    public var codex: CodexConfiguration
    public var openCode: OpenCodeConfiguration
    public var webSearch: WebSearchConfiguration
    public var monitoring: MonitoringConfiguration
    public var relaunchTargets: RelaunchTargets
    public var modelIndicator: ModelIndicator

    public init(
        version: Int = 8,
        providers: [Provider] = [],
        mappings: [String: ModelMapping] = [:],
        autoMode: Bool = true,
        connected: Bool = false,
        claudeCode: ClaudeCodeConfiguration = .disconnected,
        codex: CodexConfiguration = .disconnected,
        openCode: OpenCodeConfiguration = .disconnected,
        webSearch: WebSearchConfiguration = .disabled,
        monitoring: MonitoringConfiguration = .init(),
        relaunchTargets: RelaunchTargets = .none,
        modelIndicator: ModelIndicator = .mapsTo
    ) {
        self.version = version
        self.providers = providers
        self.mappings = mappings
        self.autoMode = autoMode
        self.connected = connected
        self.claudeCode = claudeCode
        self.codex = codex
        self.openCode = openCode
        self.webSearch = webSearch
        self.monitoring = monitoring
        self.relaunchTargets = relaunchTargets
        self.modelIndicator = modelIndicator
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case providers
        case mappings
        case autoMode
        case connected
        case claudeCode
        case codex
        case openCode
        case webSearch
        case monitoring
        case relaunchTargets
        case modelIndicator
    }

    private struct StoredProvider {
        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case baseURL
            case authMode
            case credentialSource
            case credentialScriptPath
            case credentialRefreshInterval
            case models
            case lastRefresh
            case status
            case lastError
            case maximumParallelRequests
            case imageInputOverride
            case disabledThinkingOverride
            case responsesWireOverride
            case anthropicBaseURL
            case wireProbe
        }

        static func decode(
            from decoder: Decoder,
            configurationVersion: Int
        ) throws -> Provider {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let baseURL = try values.decode(String.self, forKey: .baseURL)
            let maximumParallelRequests: Int
            if values.contains(.maximumParallelRequests) {
                maximumParallelRequests = try values.decode(
                    Int.self,
                    forKey: .maximumParallelRequests
                )
            } else if (1...6).contains(configurationVersion) {
                maximumParallelRequests = legacyMaximumParallelRequests(for: baseURL)
            } else {
                throw DecodingError.keyNotFound(
                    CodingKeys.maximumParallelRequests,
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "maximumParallelRequests is required"
                    )
                )
            }
            guard Provider.maximumParallelRequestsRange.contains(maximumParallelRequests) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .maximumParallelRequests,
                    in: values,
                    debugDescription: "maximumParallelRequests must be between 1 and 32"
                )
            }
            // Pre-header-source-split configurations stored the script
            // source as the auth mode itself: it meant "run a script, send
            // the token as a Bearer header".
            let storedAuthMode = try values.decode(String.self, forKey: .authMode)
            let legacyScriptSource = storedAuthMode == "script"
            let authMode: AuthMode
            if legacyScriptSource || storedAuthMode == "optional-bearer" {
                authMode = .bearer
            } else {
                guard let decodedMode = AuthMode(rawValue: storedAuthMode) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .authMode,
                        in: values,
                        debugDescription: "Unknown authentication mode \(storedAuthMode)"
                    )
                }
                authMode = decodedMode
            }
            let credentialSource: CredentialSource
            if let storedSource = try values.decodeIfPresent(
                CredentialSource.self,
                forKey: .credentialSource
            ) {
                credentialSource = storedSource
            } else {
                credentialSource = legacyScriptSource ? .script : .manual
            }
            return try Provider(
                id: values.decode(UUID.self, forKey: .id),
                name: values.decode(String.self, forKey: .name),
                baseURL: baseURL,
                authMode: authMode,
                credentialSource: credentialSource,
                credentialScriptPath: values.decodeIfPresent(
                    String.self,
                    forKey: .credentialScriptPath
                ),
                credentialRefreshInterval: values.decodeIfPresent(
                    TimeInterval.self,
                    forKey: .credentialRefreshInterval
                ),
                models: values.decode([DiscoveredModel].self, forKey: .models),
                lastRefresh: values.decodeIfPresent(Date.self, forKey: .lastRefresh),
                status: values.decode(ProviderStatus.self, forKey: .status),
                lastError: values.decodeIfPresent(String.self, forKey: .lastError),
                maximumParallelRequests: maximumParallelRequests,
                imageInputOverride: values.decodeIfPresent(
                    ProviderImageInputOverride.self,
                    forKey: .imageInputOverride
                ),
                disabledThinkingOverride: values.decodeIfPresent(
                    ProviderDisabledThinkingOverride.self,
                    forKey: .disabledThinkingOverride
                ),
                responsesWireOverride: values.decodeIfPresent(
                    ProviderResponsesWireOverride.self,
                    forKey: .responsesWireOverride
                ),
                anthropicBaseURL: values.decodeIfPresent(
                    String.self,
                    forKey: .anthropicBaseURL
                ),
                wireProbe: values.decodeIfPresent(
                    ProviderWireProbe.self,
                    forKey: .wireProbe
                )
            )
        }

        private static func legacyMaximumParallelRequests(for baseURL: String) -> Int {
            guard
                let normalizedURL = try? ProviderEndpoint.normalize(baseURL),
                let host = URLComponents(string: normalizedURL)?.host?.lowercased(),
                host == "api.z.ai"
            else {
                return Provider.defaultMaximumParallelRequests
            }
            return ProviderPreset.zai.maximumParallelRequests
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try values.decode(Int.self, forKey: .version)
        version = (1...7).contains(storedVersion) ? 8 : storedVersion
        var storedProviders = try values.nestedUnkeyedContainer(forKey: .providers)
        var decodedProviders: [Provider] = []
        while !storedProviders.isAtEnd {
            decodedProviders.append(
                try StoredProvider.decode(
                    from: storedProviders.superDecoder(),
                    configurationVersion: storedVersion
                )
            )
        }
        providers = decodedProviders
        let routeIDs = Set(ClaudeRoute.all.map(\.id))
        mappings =
            try values
            .decode([String: ModelMapping].self, forKey: .mappings)
            .filter { routeIDs.contains($0.key) }
        autoMode = try values.decode(Bool.self, forKey: .autoMode)
        connected = try values.decode(Bool.self, forKey: .connected)
        claudeCode =
            try values.decodeIfPresent(
                ClaudeCodeConfiguration.self,
                forKey: .claudeCode
            ) ?? .disconnected
        codex = try values.decodeIfPresent(CodexConfiguration.self, forKey: .codex) ?? .disconnected
        openCode =
            try values.decodeIfPresent(
                OpenCodeConfiguration.self,
                forKey: .openCode
            ) ?? .disconnected
        webSearch =
            try values.decodeIfPresent(
                WebSearchConfiguration.self,
                forKey: .webSearch
            ) ?? .disabled
        monitoring =
            try values.decodeIfPresent(
                MonitoringConfiguration.self,
                forKey: .monitoring
            ) ?? .init()
        relaunchTargets =
            try values.decodeIfPresent(
                RelaunchTargets.self,
                forKey: .relaunchTargets
            ) ?? .none
        // A hand-edited or forward-written raw value must not brick the whole
        // configuration decode; unknown indicators fall back to the default.
        modelIndicator =
            try values
            .decodeIfPresent(String.self, forKey: .modelIndicator)
            .flatMap(ModelIndicator.init(rawValue:))
            ?? .mapsTo
    }
}

public protocol ConfigurationStoring: Sendable {
    func load() throws -> AppConfiguration
    func save(_ configuration: AppConfiguration) throws
}

public struct ConfigurationStore: Sendable {
    public enum Error: Swift.Error, Equatable {
        case unsupportedVersion(Int)
        case invalidMaximumParallelRequests(providerID: UUID, value: Int)
    }

    private struct StoredConfigurationVersion: Decodable {
        var version: Int
    }

    public let fileURL: URL
    public let backupDirectory: URL
    public let backupLimit: Int

    public init(fileURL: URL, backupDirectory: URL, backupLimit: Int = 5) {
        self.fileURL = fileURL
        self.backupDirectory = backupDirectory
        self.backupLimit = backupLimit
    }

    public func load() throws -> AppConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AppConfiguration()
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        let storedVersion = try decoder.decode(StoredConfigurationVersion.self, from: data).version
        guard (1...8).contains(storedVersion) else {
            throw Error.unsupportedVersion(storedVersion)
        }
        let configuration = try decoder.decode(
            AppConfiguration.self,
            from: data
        )
        if storedVersion != configuration.version {
            try ConfigurationMigrationBackup.preserve(
                data,
                version: storedVersion,
                fileName: fileURL.lastPathComponent,
                backupDirectory: backupDirectory)
        }
        return configuration
    }

    public func save(_ configuration: AppConfiguration) throws {
        for provider in configuration.providers {
            guard Provider.maximumParallelRequestsRange.contains(provider.maximumParallelRequests)
            else {
                throw Error.invalidMaximumParallelRequests(
                    providerID: provider.id,
                    value: provider.maximumParallelRequests
                )
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(configuration)
        try AtomicFileWriter.write(
            data,
            to: fileURL,
            backupDirectory: backupDirectory,
            backupLimit: backupLimit
        )
    }
}

extension ConfigurationStore: ConfigurationStoring {}

public enum AtomicFileWriter {
    public static func write(
        _ data: Data,
        to destination: URL,
        backupDirectory: URL,
        backupLimit: Int = 5,
        fileManager: FileManager = .default,
        renamer: @escaping @Sendable (URL, URL) -> Int32 = { source, destination in
            guard Darwin.rename(source.path, destination.path) == 0 else {
                return errno
            }
            return 0
        }
    ) throws {
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        if backupLimit > 0, fileManager.fileExists(atPath: destination.path) {
            let backup = backupDirectory.appending(
                path: "\(destination.lastPathComponent).\(UUID().uuidString).backup"
            )
            try fileManager.copyItem(at: destination, to: backup)
        }

        let temporary = parent.appending(path: ".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        fileManager.createFile(atPath: temporary.path, contents: nil)
        do {
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            try replaceAtomically(temporary, destination: destination, renamer: renamer)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }

        if backupLimit > 0 {
            try? pruneBackups(
                for: destination.lastPathComponent,
                in: backupDirectory,
                keeping: backupLimit,
                fileManager: fileManager
            )
        }
    }

    private static func replaceAtomically(
        _ source: URL,
        destination: URL,
        renamer: @Sendable (URL, URL) -> Int32
    ) throws {
        let errorNumber = renamer(source, destination)
        guard errorNumber == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errorNumber) ?? .EIO)
        }
    }

    private static func pruneBackups(
        for filename: String,
        in directory: URL,
        keeping limit: Int,
        fileManager: FileManager
    ) throws {
        let entries = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )
        let backups =
            entries
            .filter { $0.lastPathComponent.hasPrefix("\(filename).") && $0.pathExtension == "backup" }
            .sorted { left, right in
                let leftDate = try? left.resourceValues(forKeys: [.creationDateKey]).creationDate
                let rightDate = try? right.resourceValues(forKeys: [.creationDateKey]).creationDate
                if leftDate == rightDate {
                    return left.lastPathComponent < right.lastPathComponent
                }
                return (leftDate ?? .distantPast) < (rightDate ?? .distantPast)
            }
        guard backups.count > max(0, limit) else {
            return
        }
        for backup in backups.prefix(backups.count - max(0, limit)) {
            try fileManager.removeItem(at: backup)
        }
    }
}
