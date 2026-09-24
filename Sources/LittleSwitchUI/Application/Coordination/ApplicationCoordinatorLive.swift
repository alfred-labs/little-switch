import Foundation
import LittleSwitchCore
import LittleSwitchTransport

package struct ApplicationCoordinatorLivePaths: Sendable {
    package let applicationSupport: URL?
    package let homeDirectory: URL

    package init(applicationSupport: URL?, homeDirectory: URL) {
        self.applicationSupport = applicationSupport
        self.homeDirectory = homeDirectory
    }

    package static var system: Self {
        Self(
            applicationSupport: FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }
}

package enum ApplicationCoordinatorLiveEnvironment {
    @TaskLocal package static var paths = ApplicationCoordinatorLivePaths.system
}

extension ApplicationCoordinator {
    public static func live(
        claudeController: any ClaudeApplicationControlling,
        codexController: any CodexApplicationControlling,
        desktopApplications: (any DesktopApplicationManaging)? = nil,
        trafficRecorder: any TrafficRecording = NoopTrafficRecorder()
    ) throws -> ApplicationCoordinator {
        let paths = ApplicationCoordinatorLiveEnvironment.paths
        return try live(
            applicationSupport: paths.applicationSupport,
            homeDirectory: paths.homeDirectory,
            claudeController: claudeController,
            codexController: codexController,
            desktopApplications: desktopApplications,
            trafficRecorder: trafficRecorder
        )
    }

    package static func live(
        applicationSupport: URL?,
        homeDirectory: URL,
        claudeController: any ClaudeApplicationControlling,
        codexController: any CodexApplicationControlling,
        desktopApplications: (any DesktopApplicationManaging)? = nil,
        trafficRecorder: any TrafficRecording = NoopTrafficRecorder()
    ) throws -> ApplicationCoordinator {
        // Tests exercise this composition root only with injected temporary paths and shutdown.
        // Starting it would cross the real Keychain and managed-profile adapter boundaries.
        guard let applicationSupport else {
            throw ClaudeProfileManager.Error.applicationSupportUnavailable
        }
        let root = try ProductIdentity.applicationSupportRoot(in: applicationSupport)
        let store = ConfigurationStore(
            fileURL: root.appending(path: "config.json"),
            backupDirectory: root.appending(path: "Backups/Configuration")
        )
        let profilePaths = ClaudeProfilePaths(applicationSupport: applicationSupport)
        let codexPaths = CodexProfilePaths(
            homeDirectory: homeDirectory,
            applicationSupport: applicationSupport
        )
        let claudeCodePaths = ClaudeCodeProfilePaths(
            homeDirectory: homeDirectory,
            applicationSupport: applicationSupport
        )
        let openCodePaths = OpenCodeProfilePaths(
            homeDirectory: homeDirectory,
            applicationSupport: applicationSupport
        )
        return ApplicationCoordinator(
            configurationStore: store,
            secretStore: MigratingSecretStore(
                primary: KeychainSecretStore(),
                legacy: MigratingSecretStore(
                    primary: KeychainSecretStore(
                        service: ProductIdentity.Legacy.ModelSwitch.keychainService
                    ),
                    legacy: KeychainSecretStore(
                        service: ProductIdentity.Legacy.ModelSwitcher.keychainService
                    )
                )
            ),
            profileManager: ClaudeProfileManager(paths: profilePaths),
            claudeController: claudeController,
            desktopApplications: desktopApplications,
            codexProfileManager: CodexProfileManager(paths: codexPaths),
            codexController: codexController,
            claudeCodeProfileManager: ClaudeCodeProfileManager(paths: claudeCodePaths),
            openCodeProfileManager: OpenCodeProfileManager(paths: openCodePaths),
            discoveryTransport: AsyncHTTPTransport(),
            gatewayTransportBuilder: LiveGatewayTransportBuilder(),
            gatewayFactory: LiveGatewayFactory(builder: LiveGatewayBuilder()),
            trafficRecorder: trafficRecorder,
            tlsProvisioner: LiveGatewayTLSProvisioner(),
            customToolCapabilities: CustomToolCapabilityCache(
                storeURL: root.appending(path: "Cache/CustomToolCapabilities.json")
            ),
            chatGPTGatewayBuilder: LiveChatGPTGatewayBuilder(
                historyFileURL: root.appending(path: "ChatGPT/conversations.json"),
                trafficRecorder: trafficRecorder
            )
        )
    }
}
