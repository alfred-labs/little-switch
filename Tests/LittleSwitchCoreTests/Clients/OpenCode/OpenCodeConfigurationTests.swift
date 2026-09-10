import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("OpenCode configuration")
struct OpenCodeConfigurationTests {
    private struct Fixture {
        var providers: [Provider]
        var alpha: ModelMapping
        var hidden: ModelMapping
        var beta: ModelMapping
        var codex: CodexConfiguration
    }

    @Test("Only Codex-exposed models are available")
    func availableModels() throws {
        let alphaID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let betaID = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let hidden = ModelMapping(providerID: alphaID, modelID: "hidden")
        let providers = [
            Provider(
                id: alphaID,
                name: "Alpha",
                baseURL: "https://alpha.example.com",
                authMode: .none,
                models: [DiscoveredModel(id: "hidden"), DiscoveredModel(id: "a")]
            ),
            Provider(
                id: betaID,
                name: "Beta",
                baseURL: "https://beta.example.com",
                authMode: .none,
                models: [DiscoveredModel(id: "b")]
            ),
        ]

        let available = OpenCodeConfiguration.disconnected.availableModels(
            in: providers,
            codex: CodexConfiguration(excludedModels: [hidden])
        )

        #expect(available.map(\.displayName) == ["Alpha/a", "Beta/b"])
    }

    @Test("Normalization preserves a valid independent default")
    func validIndependentDefault() throws {
        let fixture = try fixture()
        let configuration = OpenCodeConfiguration(
            connected: true,
            defaultModel: fixture.alpha
        )

        #expect(
            configuration.normalized(providers: fixture.providers, codex: fixture.codex)
                == configuration
        )
    }

    @Test("Normalization falls back to the Codex default")
    func codexDefaultFallback() throws {
        let fixture = try fixture()

        #expect(
            OpenCodeConfiguration(
                connected: true,
                defaultModel: fixture.hidden
            ).normalized(providers: fixture.providers, codex: fixture.codex)
                == OpenCodeConfiguration(connected: true, defaultModel: fixture.beta)
        )
    }

    @Test("Normalization falls back to the first exposed model when the Codex default is unavailable")
    func firstExposedFallback() throws {
        let fixture = try fixture()
        let codex = CodexConfiguration(
            defaultModel: fixture.hidden,
            excludedModels: [fixture.hidden]
        )

        #expect(
            OpenCodeConfiguration(connected: true, defaultModel: fixture.hidden)
                .normalized(providers: fixture.providers, codex: codex)
                == OpenCodeConfiguration(connected: true, defaultModel: fixture.alpha)
        )
    }

    @Test("No default resolves when Codex exposes no model")
    func noDefault() throws {
        let fixture = try fixture()
        let codex = CodexConfiguration(
            defaultModel: fixture.beta,
            excludedModels: [fixture.alpha, fixture.hidden, fixture.beta]
        )

        #expect(
            OpenCodeConfiguration(connected: true, defaultModel: fixture.beta)
                .normalized(providers: fixture.providers, codex: codex)
                == OpenCodeConfiguration(connected: true)
        )
    }

    private func fixture() throws -> Fixture {
        let alphaID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let betaID = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let alpha = ModelMapping(providerID: alphaID, modelID: "a")
        let hidden = ModelMapping(providerID: alphaID, modelID: "hidden")
        let beta = ModelMapping(providerID: betaID, modelID: "b")
        let providers = [
            Provider(
                id: alphaID,
                name: "Alpha",
                baseURL: "https://alpha.example.com",
                authMode: .none,
                models: [DiscoveredModel(id: "hidden"), DiscoveredModel(id: "a")]
            ),
            Provider(
                id: betaID,
                name: "Beta",
                baseURL: "https://beta.example.com",
                authMode: .none,
                models: [DiscoveredModel(id: "b")]
            ),
        ]
        let codex = CodexConfiguration(defaultModel: beta, excludedModels: [hidden])
        return Fixture(
            providers: providers,
            alpha: alpha,
            hidden: hidden,
            beta: beta,
            codex: codex
        )
    }
}
