import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Provider catalog parsing")
struct ProviderCatalogParsingTests {
    @Test("Catalog parsing deduplicates, trims invalid IDs, and sorts")
    func parsesCatalog() throws {
        let data = Data(
            #"{"data":[{"id":" qwen "},{"id":"glm-5.2","max_tokens":131072},{"id":"qwen"},{"id":""}]}"#.utf8)
        let models = try ProviderCatalog.parse(data)
        #expect(
            models == [
                DiscoveredModel(id: "glm-5.2", maxTokens: 131_072),
                DiscoveredModel(id: "qwen", maxTokens: nil),
            ])
    }

    @Test("Catalog parsing discovers context windows without model-name mappings")
    func parsesContextWindows() throws {
        let data = Data(
            #"""
            {"data":[
              {"id":"anthropic","max_input_tokens":1000000},
              {"id":"vllm","max_model_len":400000,"context_length":262144},
              {"id":"generic","context_length":262144},
              {"id":"fallback","context_window":128000},
              {"id":"invalid","max_input_tokens":0,"context_length":-1}
            ]}
            """#.utf8)

        let models = try ProviderCatalog.parse(data)

        #expect(models.first { $0.id == "anthropic" }?.detectedContextWindow == 1_000_000)
        #expect(models.first { $0.id == "vllm" }?.detectedContextWindow == 400_000)
        #expect(models.first { $0.id == "generic" }?.detectedContextWindow == 262_144)
        #expect(models.first { $0.id == "fallback" }?.detectedContextWindow == 128_000)
        #expect(models.first { $0.id == "invalid" }?.detectedContextWindow == nil)
    }

    @Test("Catalog parsing detects image input from modality metadata")
    func parsesImageModality() throws {
        let data = Data(
            #"""
            {"data":[
              {"id":"direct","input_modalities":["text","image"]},
              {"id":"text-only","input_modalities":["text"]},
              {"id":"archived","architecture":{"input_modalities":["image","text"]}},
              {"id":"archived-text","architecture":{"input_modalities":["text"]}},
              {"id":"opaque","context_length":262144}
            ]}
            """#.utf8)

        let models = try ProviderCatalog.parse(data)

        #expect(models.first { $0.id == "direct" }?.supportsImageInput == true)
        #expect(models.first { $0.id == "text-only" }?.supportsImageInput == false)
        #expect(models.first { $0.id == "archived" }?.supportsImageInput == true)
        #expect(models.first { $0.id == "archived-text" }?.supportsImageInput == false)
        #expect(models.first { $0.id == "opaque" }?.supportsImageInput == nil)
    }

    @Test("Ollama context parsing rejects responses without model info")
    func rejectsMissingOllamaModelInfo() {
        #expect(ProviderCatalog.parseOllamaContextWindow(Data(#"{}"#.utf8)) == nil)
    }

    @Test("Catalog parsing requires at least one model")
    func rejectsEmptyCatalog() {
        #expect(throws: ProviderCatalog.Error.self) {
            try ProviderCatalog.parse(Data(#"{"data":[]}"#.utf8))
        }
        #expect(throws: (any Swift.Error).self) {
            try ProviderCatalog.parse(Data("not-json".utf8))
        }
    }
}
