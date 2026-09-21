import Foundation
import Testing

@testable import LittleSwitchCommon

@Suite("Provider domain")
struct ProviderDomainTests {

    @Test("Providers and presets expose bounded parallel request recommendations")
    func presets() {
        #expect(Provider.maximumParallelRequestsRange == 1...32)
        #expect(Provider.defaultMaximumParallelRequests == 4)
        #expect(
            ProviderPreset(
                name: "Default",
                baseURL: "https://example.com",
                authMode: .bearer
            ).maximumParallelRequests == 4
        )
        #expect(
            Provider(
                name: "Default",
                baseURL: "https://example.com",
                authMode: .bearer
            ).maximumParallelRequests == 4
        )
        #expect(
            ProviderPreset.ollama
                == ProviderPreset(
                    name: "Ollama",
                    baseURL: "http://127.0.0.1:11434",
                    authMode: .none,
                    maximumParallelRequests: 4
                )
        )
        #expect(
            ProviderPreset.openAICompatible
                == ProviderPreset(
                    name: "OpenAI Compatible",
                    baseURL: "http://127.0.0.1:8000",
                    authMode: .bearer,
                    maximumParallelRequests: 4
                )
        )
        #expect(
            ProviderPreset.openAI
                == ProviderPreset(
                    name: "OpenAI",
                    baseURL: "https://api.openai.com",
                    authMode: .bearer,
                    maximumParallelRequests: 4
                )
        )
        #expect(
            ProviderPreset.omlx
                == ProviderPreset(
                    name: "oMLX",
                    baseURL: "http://127.0.0.1:1234",
                    authMode: .none,
                    maximumParallelRequests: 2
                )
        )
        #expect(
            ProviderPreset.lmStudio
                == ProviderPreset(
                    name: "LM Studio",
                    baseURL: "http://127.0.0.1:1234",
                    authMode: .bearer,
                    maximumParallelRequests: 2
                )
        )
        #expect(
            ProviderPreset.openRouter
                == ProviderPreset(
                    name: "OpenRouter",
                    baseURL: "https://openrouter.ai/api",
                    authMode: .bearer,
                    maximumParallelRequests: 8
                )
        )
        #expect(
            ProviderPreset.zai
                == ProviderPreset(
                    name: "z.ai",
                    baseURL: "https://api.z.ai/api/coding/paas/v4",
                    authMode: .bearer,
                    maximumParallelRequests: 2,
                    anthropicBaseURL: "https://api.z.ai/api/anthropic"
                )
        )
        #expect(
            ProviderPreset.custom
                == ProviderPreset(
                    name: "",
                    baseURL: "",
                    authMode: .none,
                    maximumParallelRequests: 4
                )
        )
    }

    @Test("A context override is only effective when detection is missing")
    func contextOverride() {
        let detected = DiscoveredModel(id: "large", detectedContextWindow: 400_000)
        let overridden = DiscoveredModel(
            id: "large",
            detectedContextWindow: 400_000,
            contextWindowOverride: 1_000_000
        )
        let unknown = DiscoveredModel(id: "unknown")
        let declaredWhenUnknown = DiscoveredModel(
            id: "declared",
            contextWindowOverride: 1_000_000
        )
        let detected1M = DiscoveredModel(id: "big", detectedContextWindow: 1_000_000)

        #expect(detected.effectiveContextWindow == 400_000)
        #expect(!detected.supports1MContext)
        #expect(overridden.effectiveContextWindow == 400_000)
        #expect(!overridden.allows1MContextOverride)
        #expect(!overridden.supports1MContext)
        #expect(!unknown.supports1MContext)
        #expect(declaredWhenUnknown.allows1MContextOverride)
        #expect(declaredWhenUnknown.supports1MContext)
        #expect(detected1M.supports1MContext)
    }

    @Test("Provider image acceptance resolves overrides before detection")
    func imageAcceptance() {
        func provider(_ override: ProviderImageInputOverride?) -> Provider {
            var instance = Provider(
                id: UUID(),
                name: "Local",
                baseURL: "http://127.0.0.1:11434",
                authMode: .none
            )
            instance.imageInputOverride = override
            return instance
        }
        let detected = DiscoveredModel(id: "glm", supportsImageInput: false)
        let undetected = DiscoveredModel(id: "qwen")

        #expect(provider(nil).imageInputsAccepted(for: detected) == false)
        #expect(provider(nil).imageInputsAccepted(for: undetected))
        #expect(provider(.enabled).imageInputsAccepted(for: detected))
        #expect(!provider(.disabled).imageInputsAccepted(for: undetected))
    }
}
