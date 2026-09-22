import Foundation
import LittleSwitchCommon

public struct CodexProfilePaths: Equatable, Sendable {
    public let config: URL
    public let catalog: URL
    public let restoreState: URL
    public let backupDirectory: URL

    public var managedFiles: [URL] {
        [config, catalog, restoreState]
    }

    public init(
        config: URL,
        catalog: URL,
        restoreState: URL,
        backupDirectory: URL
    ) {
        self.config = config
        self.catalog = catalog
        self.restoreState = restoreState
        self.backupDirectory = backupDirectory
    }

    public init(homeDirectory: URL, applicationSupport: URL) {
        let supportRoot =
            applicationSupport
            .appending(
                path: ProductIdentity.applicationSupportDirectoryName,
                directoryHint: .isDirectory
            )
        let codexRoot = supportRoot.appending(path: "Codex", directoryHint: .isDirectory)
        config =
            homeDirectory
            .appending(path: ".codex", directoryHint: .isDirectory)
            .appending(path: "config.toml")
        catalog = codexRoot.appending(path: "model-catalog.json")
        restoreState = codexRoot.appending(path: "restore.json")
        backupDirectory =
            supportRoot
            .appending(path: "Backups", directoryHint: .isDirectory)
            .appending(path: "Codex", directoryHint: .isDirectory)
    }

    public static func live(fileManager: FileManager = .default) throws -> CodexProfilePaths {
        guard
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            throw CodexProfileManager.Error.applicationSupportUnavailable
        }
        return CodexProfilePaths(
            homeDirectory: fileManager.homeDirectoryForCurrentUser,
            applicationSupport: applicationSupport
        )
    }
}

package protocol CodexProfileFileStore: Sendable {
    func snapshot(_ url: URL) throws -> Data?
    func write(_ data: Data, to url: URL) throws
    func restore(_ data: Data?, to url: URL) throws
}

public struct DiskCodexProfileFileStore: CodexProfileFileStore {
    public let backupDirectory: URL
    private let permissionsSetter: @Sendable (Int, URL) throws -> Void

    public init(
        backupDirectory: URL,
        permissionsSetter: @escaping @Sendable (Int, URL) throws -> Void = { permissions, url in
            try FileManager.default.setAttributes(
                [.posixPermissions: permissions],
                ofItemAtPath: url.path
            )
        }
    ) {
        self.backupDirectory = backupDirectory
        self.permissionsSetter = permissionsSetter
    }

    public func snapshot(_ url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    public func write(_ data: Data, to url: URL) throws {
        try AtomicFileWriter.write(
            data,
            to: url,
            backupDirectory: backupDirectory
        )
        try permissionsSetter(0o600, url)
    }

    public func restore(_ data: Data?, to url: URL) throws {
        guard let data else {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return
        }
        try write(data, to: url)
    }
}

public enum CodexProfileStatus: Equatable, Sendable {
    case inactive
    case active(CodexManagedProfileSignature)
    case requiresUpdate(CodexManagedProfileSignature)
}

public protocol CodexProfileManaging: Sendable {
    func activate(providers: [Provider], configuration: CodexConfiguration) throws
    func activate(
        providers: [Provider],
        configuration: CodexConfiguration,
        signature: CodexManagedProfileSignature
    ) throws
    func restore() throws
    func isActive(providers: [Provider], configuration: CodexConfiguration) throws -> Bool
    func status(
        providers: [Provider],
        configuration: CodexConfiguration,
        expected: CodexManagedProfileSignature
    ) throws -> CodexProfileStatus
    func enableDesktopMaximumEffort() throws
}

extension CodexProfileManaging {
    public func enableDesktopMaximumEffort() throws {}
}

extension CodexProfileManaging {
    public func activate(
        providers: [Provider],
        configuration: CodexConfiguration,
        signature: CodexManagedProfileSignature
    ) throws {
        _ = signature
        try activate(providers: providers, configuration: configuration)
    }

    public func status(
        providers: [Provider],
        configuration: CodexConfiguration,
        expected: CodexManagedProfileSignature
    ) throws -> CodexProfileStatus {
        try isActive(providers: providers, configuration: configuration)
            ? .active(expected)
            : .inactive
    }
}

public struct CodexProfileManager: Sendable {
    public enum Error: Swift.Error, Equatable {
        case applicationSupportUnavailable
        case invalidUTF8(URL)
        case rollbackFailed
    }

    private typealias RestoreState = CodexProfileRestoreState

    private struct Snapshot {
        var url: URL
        var data: Data?
    }

    public let paths: CodexProfilePaths
    private let fileStore: any CodexProfileFileStore
    private let nativeCatalog: CodexNativeCatalog?

    private var sentinel: CodexSentinelAuth {
        CodexSentinelAuth(
            configURL: paths.config,
            fileStore: DiskCodexProfileFileStore(backupDirectory: paths.backupDirectory)
        )
    }

    package init(
        paths: CodexProfilePaths,
        fileStore: (any CodexProfileFileStore)? = nil,
        nativeCatalog: CodexNativeCatalog? = nil
    ) {
        self.paths = paths
        self.fileStore =
            fileStore
            ?? DiskCodexProfileFileStore(backupDirectory: paths.backupDirectory)
        self.nativeCatalog =
            nativeCatalog
            ?? CodexNativeCatalog(
                configDirectory: paths.config.deletingLastPathComponent()
            )
    }

    public func activate(
        providers: [Provider],
        configuration: CodexConfiguration
    ) throws {
        let signature = try CodexManagedProfileSignature.resolve(
            providers: providers,
            configuration: configuration
        )
        try activate(
            providers: providers,
            configuration: configuration,
            signature: signature
        )
    }

    public func activate(
        providers: [Provider],
        configuration: CodexConfiguration,
        signature: CodexManagedProfileSignature
    ) throws {
        _ = providers
        _ = configuration
        let nativeCatalogData = nativeCatalog?.acquire()
        let catalogData = try CodexCatalog.mergedData(
            managedData: signature.catalogData,
            nativeCatalogData: nativeCatalogData
        )
        let configData = try fileStore.snapshot(paths.config)
        var configText = try text(from: configData, url: paths.config)
        var restoreState = try CodexProfileLegacyJournal.state(
            configText: configText,
            configExisted: configData != nil,
            paths: paths,
            fileStore: fileStore
        )
        restoreState.nativeCatalogData = nativeCatalogData
        configText = try restoreState.preparingWebSearch(in: configText, mode: signature.webSearchMode)
        var managedText = try CodexTOMLEditor.activating(
            configText,
            signature: signature,
            catalogPath: paths.catalog.path
        )
        if let maximum = signature.maximumConcurrentThreadsPerSession {
            let edit = try CodexAgentConcurrencyEditor.activating(
                managedText,
                maximumConcurrentThreadsPerSession: maximum,
                state: restoreState.agentConcurrency
            )
            managedText = edit.text
            restoreState.agentConcurrency = edit.state
        } else if let state = restoreState.agentConcurrency {
            managedText = try CodexAgentConcurrencyEditor.restoring(
                managedText,
                state: state
            )
            restoreState.agentConcurrency = nil
        }
        let stateData = try encode(restoreState)

        try transaction {
            try fileStore.write(stateData, to: paths.restoreState)
            try fileStore.write(catalogData, to: paths.catalog)
            try fileStore.write(Data(managedText.utf8), to: paths.config)
        }
        try sentinel.installIfAbsent()
        try? enableDesktopMaximumEffort()
    }

    public func enableDesktopMaximumEffort() throws {
        let globalState = paths.config
            .deletingLastPathComponent()
            .appending(path: ".codex-global-state.json")
        let updated = try CodexGlobalState.enablingMaximumReasoningEffort(
            in: fileStore.snapshot(globalState)
        )
        guard let updated else {
            return
        }
        try fileStore.write(updated, to: globalState)
    }

    public func restore() throws {
        let configData = try fileStore.snapshot(paths.config)
        guard let configData else {
            try transaction {
                try fileStore.restore(nil, to: paths.catalog)
                try fileStore.restore(nil, to: paths.restoreState)
            }
            try sentinel.removeIfManaged()
            return
        }
        let configText = try text(from: configData, url: paths.config)
        let stateData = try fileStore.snapshot(paths.restoreState)
        let state = try stateData.map {
            try CodexProfileLegacyJournal.decoded($0, configText: configText)
        }
        let wasManaged = try CodexTOMLEditor.rootIsManaged(
            configText,
            catalogPath: paths.catalog.path
        )
        let wasLegacyManaged = try CodexTOMLEditor.rootIsLegacyManaged(
            configText,
            catalogPath: paths.catalog.path
        )

        var restoredText = configText
        if let agentConcurrency = state?.agentConcurrency {
            restoredText = try CodexAgentConcurrencyEditor.restoring(
                restoredText,
                state: agentConcurrency
            )
        }
        if wasManaged || wasLegacyManaged {
            var rootValues = state?.rootValues ?? Self.emptyRootValues
            if state == nil, wasLegacyManaged {
                // The legacy provider profile never owned this root key.
                rootValues.removeValue(forKey: "openai_base_url")
            }
            restoredText = try CodexTOMLEditor.restoring(
                restoredText,
                states: rootValues
            )
        }
        let ownsProvider =
            try CodexTOMLEditor.rootString("model_provider", in: restoredText)
            == CodexTOMLEditor.providerID
        if !ownsProvider {
            restoredText = try CodexTOMLEditor.removingOwnedProvider(from: restoredText)
        }
        let catalogIsReferenced =
            try CodexTOMLEditor.rootString("model_catalog_json", in: restoredText)
            == paths.catalog.path
        let shouldRemoveConfig =
            (wasManaged || wasLegacyManaged)
            && state?.configExisted == false
            && restoredText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        try transaction {
            if shouldRemoveConfig {
                try fileStore.restore(nil, to: paths.config)
            } else {
                try fileStore.write(Data(restoredText.utf8), to: paths.config)
            }
            if !catalogIsReferenced {
                try fileStore.restore(nil, to: paths.catalog)
            }
            try fileStore.restore(nil, to: paths.restoreState)
        }
        try sentinel.removeIfManaged()
    }

    public func isActive(
        providers: [Provider],
        configuration: CodexConfiguration
    ) throws -> Bool {
        let expected: CodexManagedProfileSignature
        do {
            expected = try CodexManagedProfileSignature.resolve(
                providers: providers,
                configuration: configuration
            )
        } catch CodexCatalog.Error.empty {
            return false
        }
        return try status(expected: expected) == .active(expected)
    }

    public func status(
        providers: [Provider],
        configuration: CodexConfiguration,
        expected: CodexManagedProfileSignature
    ) throws -> CodexProfileStatus {
        try status(
            expected: expected,
            legacyIdentifiers: expected.withLegacyModelIdentifiers(providers: providers, configuration: configuration))
    }

    public func status(
        expected: CodexManagedProfileSignature
    ) throws -> CodexProfileStatus {
        try status(expected: expected, legacyIdentifiers: nil)
    }

    private func status(
        expected: CodexManagedProfileSignature,
        legacyIdentifiers: CodexManagedProfileSignature?
    ) throws -> CodexProfileStatus {
        guard let configData = try fileStore.snapshot(paths.config),
            let catalogData = try fileStore.snapshot(paths.catalog),
            let stateData = try fileStore.snapshot(paths.restoreState)
        else {
            return .inactive
        }
        let configText = try text(from: configData, url: paths.config)
        let state = try JSONDecoder().decode(RestoreState.self, from: stateData)
        let profile = try CodexTOMLEditor.rootString("profile", in: configText)
        let model = try CodexTOMLEditor.rootString("model", in: configText)
        let provider = try CodexTOMLEditor.rootString("model_provider", in: configText)
        let openAIBaseURL = try CodexTOMLEditor.rootString("openai_base_url", in: configText)
        let catalog = try CodexTOMLEditor.rootString("model_catalog_json", in: configText)
        guard profile == nil,
            provider == nil,
            openAIBaseURL == CodexTOMLEditor.baseURL,
            catalog == paths.catalog.path
        else {
            return .inactive
        }
        guard
            let catalogSignature = try CodexProfileSignatureMatcher.matching(
                modelSlug: model,
                catalogData: catalogData,
                nativeCatalogData: state.nativeCatalogData,
                expected: expected,
                legacyIdentifiers: legacyIdentifiers)
        else {
            return .inactive
        }
        return state.status(in: configText, expected: expected, catalogSignature: catalogSignature)
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

    private func text(from data: Data?, url: URL) throws -> String {
        guard let data else {
            return ""
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw Error.invalidUTF8(url)
        }
        return text
    }

    private func encode(_ state: RestoreState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(state)
    }

    private static let rootKeys = CodexTOMLEditor.journaledRootKeys

    private static let emptyRootValues = Dictionary(
        // A missing journal cannot prove that an older profile owned search.
        uniqueKeysWithValues: rootKeys.filter { $0 != "web_search" }.map {
            ($0, CodexRootStringState(wasPresent: false, value: ""))
        }
    )
}

extension CodexProfileManager: CodexProfileManaging {}
