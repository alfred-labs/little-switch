import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Claude gateway profile ownership")
struct ClaudeProfileOwnershipTests {
    @Test("A released profile without catalog presentation stays connected", arguments: [false, true])
    func releasedProfileRemainsActive(tlsEnabled: Bool) throws {
        let fixture = try ProfileFixture()
        defer { fixture.remove() }
        try fixture.writeConfiguration(configuration())
        try fixture.writeReleasedProfile(tlsEnabled: tlsEnabled)
        let before = try fixture.snapshots()

        #expect(try ClaudeProfileManager(paths: fixture.paths).isActive(autoMode: true))
        #expect(try fixture.snapshots() == before)
    }

    @Test("Changing catalog inputs does not relinquish profile ownership", arguments: CatalogChange.allCases)
    func changedConfigurationRemainsActive(change: CatalogChange) throws {
        let fixture = try ProfileFixture()
        defer { fixture.remove() }
        var configuration = configuration()
        try fixture.writeConfiguration(configuration)
        let manager = ClaudeProfileManager(paths: fixture.paths)
        try manager.activate(autoMode: true, tlsEnabled: true)
        #expect(try manager.isActive(autoMode: true))
        let before = try fixture.snapshots()

        switch change {
        case .indicator:
            configuration.modelIndicator = .swap
        case .contextCapacity:
            configuration.providers[0].models[0].detectedContextWindow = 1_000_000
        case .mapping:
            configuration.mappings["claude-opus-5"] = configuration.mappings["claude-sonnet-5"]
        }
        try fixture.writeConfiguration(configuration)

        #expect(try manager.isActive(autoMode: true))
        #expect(try fixture.snapshots() == before)
    }

    @Test("Catalog presentation values cannot change gateway ownership", arguments: CatalogPresentation.allCases)
    func presentationRemainsActive(presentation: CatalogPresentation) throws {
        let fixture = try ProfileFixture()
        defer { fixture.remove() }
        try fixture.writeConfiguration(configuration())
        let manager = ClaudeProfileManager(paths: fixture.paths)
        try manager.activate(autoMode: true, tlsEnabled: true)
        var profile = try fixture.object(at: fixture.paths.profile)
        switch presentation {
        case .missingDiscovery:
            profile.removeValue(forKey: "modelDiscoveryEnabled")
        case .malformedDiscovery:
            profile["modelDiscoveryEnabled"] = "enabled"
        case .missingModels:
            profile.removeValue(forKey: "inferenceModels")
        case .malformedModels:
            profile["inferenceModels"] = "invalid catalog"
        case .foreignModels:
            profile["inferenceModels"] = [["name": "corporate-model", "labelOverride": "Corporate"]]
        }
        try fixture.writeJSON(profile, to: fixture.paths.profile)
        let before = try fixture.snapshots()

        #expect(try manager.isActive(autoMode: true))
        #expect(try fixture.snapshots() == before)
    }

    @Test("A foreign profile or changed gateway connection is not owned", arguments: OwnershipChange.allCases)
    func rejectsChangedOwnership(change: OwnershipChange) throws {
        let fixture = try ProfileFixture()
        defer { fixture.remove() }
        try fixture.writeConfiguration(configuration())
        let manager = ClaudeProfileManager(paths: fixture.paths)
        try manager.activate(autoMode: true, tlsEnabled: true)
        #expect(try manager.isActive(autoMode: true))

        let mutation: OwnershipMutation
        switch change {
        case .normalMode:
            mutation = OwnershipMutation(url: fixture.paths.normalConfig, key: "deploymentMode", value: "1p")
        case .thirdPartyMode:
            mutation = OwnershipMutation(url: fixture.paths.thirdPartyConfig, key: "deploymentMode", value: "1p")
        case .appliedProfile:
            mutation = OwnershipMutation(url: fixture.paths.metadata, key: "appliedId", value: "another-profile")
        case .provider:
            mutation = OwnershipMutation(url: fixture.paths.profile, key: "inferenceProvider", value: "bedrock")
        case .displayName:
            mutation = OwnershipMutation(
                url: fixture.paths.profile, key: "deploymentDisplayName", value: "Corporate gateway")
        case .apiKey:
            mutation = OwnershipMutation(
                url: fixture.paths.profile, key: "inferenceGatewayApiKey", value: "synthetic-foreign-key")
        case .endpoint:
            mutation = OwnershipMutation(
                url: fixture.paths.profile, key: "inferenceGatewayBaseUrl", value: "https://example.com")
        case .autoMode:
            mutation = OwnershipMutation(url: fixture.paths.profile, key: "autoModeEnabled", value: false)
        }
        var object = try fixture.object(at: mutation.url)
        object[mutation.key] = mutation.value
        try fixture.writeJSON(object, to: mutation.url)
        let before = try fixture.snapshots()

        #expect(try !manager.isActive(autoMode: true))
        #expect(try fixture.snapshots() == before)
    }

    private func configuration() -> AppConfiguration {
        let provider = Provider(
            name: "Fixture",
            baseURL: "https://example.com",
            authMode: .none,
            models: [DiscoveredModel(id: "model", detectedContextWindow: 200_000)]
        )
        return AppConfiguration(
            providers: [provider],
            mappings: ["claude-sonnet-5": ModelMapping(providerID: provider.id, modelID: "model")]
        )
    }
}

extension ClaudeProfileOwnershipTests {
    private struct OwnershipMutation {
        let url: URL
        let key: String
        let value: Any
    }

    enum CatalogChange: CaseIterable, Sendable {
        case indicator, contextCapacity, mapping
    }

    enum CatalogPresentation: CaseIterable, Sendable {
        case missingDiscovery, malformedDiscovery, missingModels, malformedModels, foreignModels
    }

    enum OwnershipChange: CaseIterable, Sendable {
        case normalMode, thirdPartyMode, appliedProfile, provider, displayName, apiKey, endpoint, autoMode
    }
}

extension ProfileFixture {
    fileprivate func writeConfiguration(_ configuration: AppConfiguration) throws {
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration)) as? [String: Any])
        try writeJSON(object, to: paths.littleSwitchConfig)
    }

    fileprivate func writeReleasedProfile(tlsEnabled: Bool) throws {
        // This is the complete profile shape written by 0.6.2, constructed
        // independently of the current activation path so upgrades stay covered.
        try writeJSON(["deploymentMode": "3p"], to: paths.normalConfig)
        try writeJSON(["deploymentMode": "3p"], to: paths.thirdPartyConfig)
        try writeJSON(
            [
                "appliedId": ClaudeProfileIdentity.id,
                "entries": [["id": ClaudeProfileIdentity.id, "name": "LittleSwitch"]],
            ], to: paths.metadata)
        try writeJSON(
            [
                "inferenceProvider": "gateway",
                "inferenceGatewayBaseUrl": tlsEnabled ? "https://127.0.0.1:11436" : "http://127.0.0.1:11436",
                "inferenceGatewayApiKey": ClaudeProfileIdentity.gatewayAPIKey,
                "inferenceGatewayAuthScheme": "bearer",
                "deploymentDisplayName": "LittleSwitch",
                "chatTabEnabled": true,
                "disableDeploymentModeChooser": true,
                "coworkEgressAllowedHosts": ["*"],
                "disableEssentialTelemetry": true,
                "disableNonessentialTelemetry": true,
                "autoModeEnabled": true,
                "allowedPluginMarketplaces": [
                    ["source": "github", "repo": "anthropics/claude-plugins-official"],
                    ["source": "github", "repo": "anthropics/knowledge-work-plugins"],
                ],
            ], to: paths.profile)
    }
}
