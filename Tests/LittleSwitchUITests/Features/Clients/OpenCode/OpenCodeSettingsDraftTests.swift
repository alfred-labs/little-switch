import Foundation
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@Suite("OpenCode settings draft")
struct OpenCodeSettingsDraftTests {
    @Test("Initialization mirrors persisted OpenCode state")
    func initialization() {
        let providerID = UUID()
        let mapping = ModelMapping(providerID: providerID, modelID: "model")
        let configuration = AppConfiguration(
            openCode: OpenCodeConfiguration(connected: true, defaultModel: mapping)
        )

        #expect(
            OpenCodeSettingsDraft(configuration: configuration)
                == OpenCodeSettingsDraft(defaultModel: mapping)
        )
    }

    @Test("A draft applies only the OpenCode default and preserves connection state")
    func applying() {
        let fixture = draftFixture()
        let configuration = AppConfiguration(
            providers: fixture.providers,
            autoMode: false,
            connected: true,
            claudeCode: ClaudeCodeConfiguration(connected: true),
            codex: CodexConfiguration(
                connected: true,
                defaultModel: fixture.beta,
                excludedModels: [fixture.hidden]
            ),
            openCode: OpenCodeConfiguration(
                connected: true,
                defaultModel: fixture.beta
            ),
            webSearch: .firecrawlCloud
        )

        let applied = OpenCodeSettingsDraft(defaultModel: fixture.alpha)
            .applying(to: configuration)

        #expect(applied.openCode == OpenCodeConfiguration(connected: true, defaultModel: fixture.alpha))
        #expect(applied.providers == configuration.providers)
        #expect(applied.autoMode == configuration.autoMode)
        #expect(applied.connected == configuration.connected)
        #expect(applied.claudeCode == configuration.claudeCode)
        #expect(applied.codex == configuration.codex)
        #expect(applied.webSearch == configuration.webSearch)
    }

    @Test("Applying normalizes against committed Codex exposure")
    func committedExposure() {
        let fixture = draftFixture()
        let configuration = AppConfiguration(
            providers: fixture.providers,
            codex: CodexConfiguration(
                defaultModel: fixture.beta,
                excludedModels: [fixture.hidden]
            ),
            openCode: OpenCodeConfiguration(defaultModel: fixture.beta)
        )

        #expect(
            OpenCodeSettingsDraft(defaultModel: fixture.hidden)
                .applying(to: configuration).openCode.defaultModel == fixture.beta
        )
    }

    @Test("Reconciliation follows the effective provider and Codex exposure")
    func reconciliation() {
        let fixture = draftFixture()
        var effective = AppConfiguration(
            providers: fixture.providers,
            codex: CodexConfiguration(defaultModel: fixture.beta),
            openCode: OpenCodeConfiguration(defaultModel: fixture.alpha)
        )

        #expect(
            OpenCodeSettingsDraft(defaultModel: fixture.alpha)
                .reconciled(with: effective)
                == OpenCodeSettingsDraft(defaultModel: fixture.alpha)
        )

        effective.codex.excludedModels = [fixture.alpha, fixture.hidden]
        #expect(
            OpenCodeSettingsDraft(defaultModel: fixture.alpha)
                .reconciled(with: effective)
                == OpenCodeSettingsDraft(defaultModel: fixture.beta)
        )

        effective.providers.removeAll { $0.id == fixture.beta.providerID }
        #expect(
            OpenCodeSettingsDraft(defaultModel: fixture.beta)
                .reconciled(with: effective)
                == OpenCodeSettingsDraft(defaultModel: nil)
        )
    }

    @Test("A draft equal to the baseline compares equal after reconciliation")
    func baselineEquality() {
        let fixture = draftFixture()
        let configuration = AppConfiguration(
            providers: fixture.providers,
            codex: CodexConfiguration(defaultModel: fixture.beta),
            openCode: OpenCodeConfiguration(defaultModel: fixture.alpha)
        )
        let baseline = OpenCodeSettingsDraft(configuration: configuration)

        #expect(baseline.reconciled(with: configuration) == baseline)
    }
}

private struct DraftFixture {
    var providers: [Provider]
    var alpha: ModelMapping
    var hidden: ModelMapping
    var beta: ModelMapping
}

private func draftFixture() -> DraftFixture {
    let alphaID = UUID()
    let betaID = UUID()
    let alpha = ModelMapping(providerID: alphaID, modelID: "alpha")
    let hidden = ModelMapping(providerID: alphaID, modelID: "hidden")
    let beta = ModelMapping(providerID: betaID, modelID: "beta")
    return DraftFixture(
        providers: [
            Provider(
                id: alphaID,
                name: "Alpha",
                baseURL: "https://alpha.example.com",
                authMode: .none,
                models: [DiscoveredModel(id: "alpha"), DiscoveredModel(id: "hidden")]
            ),
            Provider(
                id: betaID,
                name: "Beta",
                baseURL: "https://beta.example.com",
                authMode: .none,
                models: [DiscoveredModel(id: "beta")]
            ),
        ],
        alpha: alpha,
        hidden: hidden,
        beta: beta
    )
}
