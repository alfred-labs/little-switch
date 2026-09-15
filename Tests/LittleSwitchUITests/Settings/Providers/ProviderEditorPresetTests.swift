import Testing

@testable import LittleSwitchUI

@Suite("Provider editor presets")
struct ProviderEditorPresetTests {
    @Test("Every provider preset has a localized title")
    func everyProviderPresetHasALocalizedTitle() {
        let expected = [
            L10n.string("Ollama"),
            L10n.string("OpenAI"),
            L10n.string("oMLX"),
            L10n.string("LM Studio"),
            L10n.string("z.ai"),
            L10n.string("OpenRouter"),
            L10n.string("OpenAI Compatible"),
            L10n.string("Custom"),
        ]

        #expect(ProviderEditorPreset.allCases.map(\.title) == expected)
    }
}
