import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Codex managed profile signature")
struct CodexManagedProfileSignatureTests {
    @Test("Resolution merges the native catalog behind the managed entries")
    func resolvesWithNativeCatalog() throws {
        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "qwen")]
        )
        let native = Data(
            #"{"models":[{"slug":"gpt-5.6-sol","display_name":"GPT-5.6 Sol"}]}"#.utf8
        )

        let signature = try CodexManagedProfileSignature.resolve(
            providers: [provider],
            configuration: CodexConfiguration(
                defaultModel: ModelMapping(providerID: providerID, modelID: "qwen")
            ),
            nativeCatalogData: native
        )

        let root = try #require(
            JSONSerialization.jsonObject(with: signature.catalogData) as? [String: Any]
        )
        let models = try #require(root["models"] as? [[String: Any]])
        let slugs = models.compactMap { $0["slug"] as? String }
        #expect(slugs == ["local/qwen", "gpt-5.6-sol", "little-switch-auto-review"])
        let nativeEntry = try #require(models.first { ($0["slug"] as? String) == "gpt-5.6-sol" })
        #expect(nativeEntry["supported_in_api"] as? Bool == false)
    }

    @Test("Resolution uses the selected default provider and exact catalog")
    func selectedProviderAndCatalog() throws {
        let fixture = makeFixture(selectedLimit: 7, unrelatedLimit: 32)

        let signature = try CodexManagedProfileSignature.resolve(
            providers: fixture.providers,
            configuration: fixture.configuration
        )

        #expect(signature.modelSlug == CodexCatalog.slug(for: fixture.defaultModel, in: fixture.providers))
        #expect(
            signature.catalogData
                == (try CodexCatalog.encode(
                    providers: fixture.providers,
                    configuration: fixture.configuration
                ))
        )
        #expect(signature.maximumConcurrentThreadsPerSession == 7)
        #expect(signature.webSearchMode == "live")
    }

    @Test("Native concurrency mirrors the provider limit and floors the hint at one")
    func nativeConcurrencyBounds() throws {
        for (providerLimit, expected) in [(Int.min, 1), (1, 1), (2, 2), (32, 32)] {
            let fixture = makeFixture(
                selectedLimit: providerLimit,
                unrelatedLimit: 4
            )

            let signature = try CodexManagedProfileSignature.resolve(
                providers: fixture.providers,
                configuration: fixture.configuration
            )

            #expect(signature.maximumConcurrentThreadsPerSession == expected)
        }
    }

    @Test("Empty model exposure is rejected")
    func emptyExposure() {
        #expect(throws: CodexCatalog.Error.empty) {
            try CodexManagedProfileSignature.resolve(
                providers: [],
                configuration: .disconnected
            )
        }
    }

    @Test("Only the explicit legacy copy omits native concurrency")
    func legacyWithoutNativeConcurrency() throws {
        let fixture = makeFixture(selectedLimit: 4, unrelatedLimit: 31)
        let signature = try CodexManagedProfileSignature.resolve(
            providers: fixture.providers,
            configuration: fixture.configuration
        )

        let legacy = signature.withoutNativeConcurrency()

        #expect(signature.maximumConcurrentThreadsPerSession == 4)
        #expect(legacy.modelSlug == signature.modelSlug)
        #expect(legacy.catalogData == signature.catalogData)
        #expect(legacy.maximumConcurrentThreadsPerSession == nil)
        #expect(legacy.webSearchMode == "live")
    }

    @Test("Legacy web search ownership is independent from native concurrency")
    func legacyWebSearchOwnership() throws {
        let fixture = makeFixture(selectedLimit: 4, unrelatedLimit: 31)
        let signature = try CodexManagedProfileSignature.resolve(
            providers: fixture.providers, configuration: fixture.configuration
        )
        let legacy = signature.withoutManagedWebSearch()

        #expect(legacy != signature)
        #expect(legacy.webSearchMode == nil)
        #expect(legacy.modelSlug == signature.modelSlug)
        #expect(legacy.catalogData == signature.catalogData)
        #expect(legacy.maximumConcurrentThreadsPerSession == 4)
        #expect(legacy.withoutNativeConcurrency() == signature.withoutNativeConcurrency().withoutManagedWebSearch())
    }

    private struct Fixture {
        let providers: [Provider]
        let configuration: CodexConfiguration
        let defaultModel: ModelMapping
    }

    private func makeFixture(
        selectedLimit: Int,
        unrelatedLimit: Int
    ) -> Fixture {
        let selectedID = UUID()
        let unrelatedID = UUID()
        let defaultModel = ModelMapping(providerID: selectedID, modelID: "selected")
        return Fixture(
            providers: [
                Provider(
                    id: unrelatedID,
                    name: "Unrelated",
                    baseURL: "https://example.com",
                    authMode: .bearer,
                    models: [DiscoveredModel(id: "other")],
                    maximumParallelRequests: unrelatedLimit
                ),
                Provider(
                    id: selectedID,
                    name: "Selected",
                    baseURL: "http://127.0.0.1:11434",
                    authMode: .none,
                    models: [DiscoveredModel(id: defaultModel.modelID)],
                    maximumParallelRequests: selectedLimit
                ),
            ],
            configuration: CodexConfiguration(defaultModel: defaultModel),
            defaultModel: defaultModel
        )
    }
}
