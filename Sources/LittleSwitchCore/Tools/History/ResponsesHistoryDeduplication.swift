import Foundation

/// Providers pattern-complete on their own replayed history: a run of
/// identical consecutive tool exchanges teaches weaker models to re-issue
/// the call forever (observed: five identical `get_goal` null pairs lock a
/// model into an endless loop that three leave healthy). Runs are capped at
/// the goal protocol's own recurrence threshold — three consecutive turns —
/// so the recurrence signal survives while the self-imitation trigger does
/// not. The newest exchanges are the ones kept.
package enum ResponsesHistoryDeduplication {
    package static let repeatedExchangeCap = 3

    package static func collapsed(_ items: [[String: Any]]) -> [[String: Any]] {
        var collapsed: [[String: Any]] = []
        collapsed.reserveCapacity(items.count)
        var index = 0
        while index < items.count {
            let item = items[index]
            let pairsCall = item["type"] as? String == "function_call"
            let pairsOutput =
                pairsCall
                && index + 1 < items.count
                && items[index + 1]["type"] as? String == "function_call_output"
            guard pairsOutput else {
                collapsed.append(item)
                index += 1
                continue
            }
            let key = exchangeKey(call: item, output: items[index + 1])
            var runEnd = index + 2
            var extending = true
            while extending {
                let inBounds = runEnd + 1 < items.count
                let nextIsPair =
                    inBounds
                    && items[runEnd]["type"] as? String == "function_call"
                    && items[runEnd + 1]["type"] as? String == "function_call_output"
                let sameExchange =
                    nextIsPair
                    && exchangeKey(call: items[runEnd], output: items[runEnd + 1]) == key
                extending = sameExchange
                if extending {
                    runEnd += 2
                }
            }
            let runLength = (runEnd - index) / 2
            if runLength > repeatedExchangeCap {
                let keepFrom = runEnd - repeatedExchangeCap * 2
                collapsed.append(contentsOf: items[keepFrom..<runEnd])
            } else {
                collapsed.append(contentsOf: items[index..<runEnd])
            }
            index = runEnd
        }
        return collapsed
    }

    /// A deterministic deep-equality key: JSON encoding of the exchange's
    /// identifying fields. An exchange that cannot encode never collapses.
    package static func exchangeKey(
        call: [String: Any],
        output: [String: Any]
    ) -> String {
        let object: [String: Any] = [
            "name": call["name"] as Any,
            "arguments": call["arguments"] as Any,
            "output": output["output"] as Any,
        ]
        let encoded: Data?
        if JSONSerialization.isValidJSONObject(object) {
            encoded = try? JSONSerialization.data(
                withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]
            )
        } else {
            encoded = nil
        }
        // An exchange that cannot encode never collapses; JSONSerialization
        // guarantees UTF-8 for the ones that do.
        guard let encoded else {
            return UUID().uuidString
        }
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: encoded, as: UTF8.self)
    }
}
