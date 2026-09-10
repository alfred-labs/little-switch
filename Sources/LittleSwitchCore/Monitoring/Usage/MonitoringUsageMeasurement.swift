import Foundation

/// Strict provider counts: booleans, negative values, strings and overflow
/// cannot masquerade as reported usage. Explicit zero remains a measurement.
private struct MonitoringTokenCount: Decodable {
    let value: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(Int.self)
        guard value >= 0 else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Negative token count")
        }
    }
}

package enum MonitoringUsageMeasurement {
    private struct Details: Decodable {
        let cached: MonitoringTokenCount?
        let written: MonitoringTokenCount?

        enum CodingKeys: String, CodingKey {
            case cached = "cached_tokens"
            case written = "cache_write_tokens"
        }
    }

    private struct Document: Decodable {
        let values: [String: MonitoringTokenCount]
        let details: Details?

        enum CodingKeys: String, CodingKey, CaseIterable {
            case input = "input_tokens"
            case prompt = "prompt_tokens"
            case output = "output_tokens"
            case completion = "completion_tokens"
            case cacheRead = "cache_read_input_tokens"
            case cacheWrite = "cache_creation_input_tokens"
            case inputDetails = "input_tokens_details"
            case promptDetails = "prompt_tokens_details"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            var counts: [String: MonitoringTokenCount] = [:]
            for key in CodingKeys.allCases where key != .inputDetails && key != .promptDetails {
                if container.contains(key) {
                    counts[key.rawValue] = try container.decode(MonitoringTokenCount.self, forKey: key)
                }
            }
            values = counts
            if container.contains(.inputDetails) {
                details = try container.decode(Details.self, forKey: .inputDetails)
            } else {
                details = try container.decodeIfPresent(Details.self, forKey: .promptDetails)
            }
        }
    }

    package static func decode(_ data: Data) throws -> GatewayUsageTotals? {
        // JSONDecoder skips decoding unknown strings, including their UTF-8 validity.
        guard String(bytes: data, encoding: .utf8) != nil else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid UTF-8 usage."))
        }
        let document = try JSONDecoder().decode(Document.self, from: data)
        let values = document.values
        let read = document.details?.cached?.value
        let written = document.details?.written?.value
        guard !values.isEmpty || read != nil || written != nil else { return nil }
        let input = values["input_tokens"]?.value ?? values["prompt_tokens"]?.value ?? 0
        let included = saturatedGatewayUsageSum(read ?? 0, written ?? 0)
        return GatewayUsageTotals(
            inputTokens: max(0, input - included),
            outputTokens: values["output_tokens"]?.value ?? values["completion_tokens"]?.value ?? 0,
            cacheReadTokens: values["cache_read_input_tokens"]?.value ?? read ?? 0,
            cacheWriteTokens: values["cache_creation_input_tokens"]?.value ?? written ?? 0
        )
    }
}
