import Foundation
import LittleSwitchCommon
import Testing

@Suite("Detected model context is authoritative")
struct ModelContextPolicyTests {
    @Test(
        "A known capacity ignores legacy manual values",
        arguments: [32_768, 999_999, 1_000_000, 1_048_576],
        [nil, 200_000, 1_000_000, 2_000_000] as [Int?]
    )
    func detectedCapacity(tokens: Int, override: Int?) {
        let model = DiscoveredModel(
            id: "model", detectedContextWindow: tokens, contextWindowOverride: override
        )

        #expect(model.effectiveContextWindow == tokens)
        #expect(!model.allows1MContextOverride)
        #expect(model.supports1MContext == (tokens >= 1_000_000))
    }

    @Test("An unknown capacity can be declared manually", arguments: [nil, 200_000, 1_000_000, 1_048_576] as [Int?])
    func unknownCapacity(override: Int?) {
        let model = DiscoveredModel(id: "model", contextWindowOverride: override)

        #expect(model.effectiveContextWindow == override)
        #expect(model.allows1MContextOverride)
        #expect(model.supports1MContext == (override.map { $0 >= 1_000_000 } ?? false))
    }

    @Test("Previously persisted overrides cannot mask detected 1M support")
    func persistedOverride() throws {
        let data = Data(
            #"{"id":"large","detected_context_window":1048576,"context_window_override":200000}"#.utf8
        )
        let model = try JSONDecoder().decode(DiscoveredModel.self, from: data)

        #expect(model.effectiveContextWindow == 1_048_576)
        #expect(model.supports1MContext)
    }
}
