import Foundation
import LittleSwitchCommon

public enum ProviderCatalog {
    public enum Error: Swift.Error, Equatable {
        case empty
    }

    public static func parse(_ data: Data) throws -> [DiscoveredModel] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        var byID: [String: DiscoveredModel] = [:]
        for item in response.data {
            let id = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else {
                continue
            }
            let maxTokens = item.maxTokens.flatMap { $0 > 0 ? $0 : nil }
            let detectedContextWindow = [
                item.maxInputTokens,
                item.maxModelLength,
                item.contextLength,
                item.contextWindow,
            ]
            .lazy
            .compactMap(\.self)
            .first { $0 > 0 }
            byID[id] = DiscoveredModel(
                id: id,
                maxTokens: maxTokens,
                detectedContextWindow: detectedContextWindow,
                supportsImageInput: item.supportsImageInput
            )
        }
        guard !byID.isEmpty else {
            throw Error.empty
        }
        return byID.values.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    public static func isOllamaVersion(_ data: Data) -> Bool {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let version = object["version"] as? String
        else {
            return false
        }
        return !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func parseOllamaContextWindow(_ data: Data) -> Int? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let modelInfo = object["model_info"] as? [String: Any]
        else {
            return nil
        }
        return modelInfo.compactMap { key, value -> Int? in
            guard key == "context_length" || key.hasSuffix(".context_length"),
                let number = value as? NSNumber,
                number.intValue > 0
            else {
                return nil
            }
            return number.intValue
        }
        .max()
    }

    private struct Response: Decodable {
        var data: [Item]
    }

    private struct Architecture: Decodable {
        var inputModalities: [String]?

        private enum CodingKeys: String, CodingKey {
            case inputModalities = "input_modalities"
        }
    }

    private struct Item: Decodable {
        var id: String
        var maxTokens: Int?
        var maxInputTokens: Int?
        var maxModelLength: Int?
        var contextLength: Int?
        var contextWindow: Int?
        var architecture: Architecture?
        var inputModalities: [String]?

        private enum CodingKeys: String, CodingKey {
            case id
            case maxTokens = "max_tokens"
            case maxInputTokens = "max_input_tokens"
            case maxModelLength = "max_model_len"
            case contextLength = "context_length"
            case contextWindow = "context_window"
            case architecture
            case inputModalities = "input_modalities"
        }

        var supportsImageInput: Bool? {
            let modalities = inputModalities ?? architecture?.inputModalities
            return modalities.map { $0.contains("image") }
        }
    }
}
