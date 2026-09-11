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

    /// Compare canonical history before either wire converts or drops items.
    /// Even unreadable mail is a boundary between distinct repetition runs.
    package static func rewritten(_ request: [String: Any]) -> [String: Any]? {
        guard let input = request["input"] as? [[String: Any]] else { return nil }
        let collapsed = collapsed(input)
        guard collapsed.count != input.count else { return nil }
        var result = request
        result["input"] = collapsed
        return result
    }

    package static func collapsed(_ items: [[String: Any]]) -> [[String: Any]] {
        var collapsed: [[String: Any]] = []
        collapsed.reserveCapacity(items.count)
        var index = 0
        while index < items.count {
            guard let key = pairKey(items, at: index) else {
                collapsed.append(items[index])
                index += 1
                continue
            }
            var runEnd = index + 2
            while pairKey(items, at: runEnd) == key { runEnd += 2 }
            let keepFrom = max(index, runEnd - repeatedExchangeCap * 2)
            collapsed.append(contentsOf: items[keepFrom..<runEnd])
            index = runEnd
        }
        return collapsed
    }

    private static func pairKey(_ items: [[String: Any]], at index: Int) -> Data? {
        guard index + 1 < items.count,
            let kind = items[index]["type"] as? String,
            ["function_call", "custom_tool_call"].contains(kind),
            items[index + 1]["type"] as? String == "\(kind)_output",
            let callID = nonemptyResponsesString(items[index]["call_id"]),
            items[index + 1]["call_id"] as? String == callID
        else { return nil }
        return exchangeKey(call: items[index], output: items[index + 1])
    }

    /// Ignore occurrence IDs only. Namespace, status and other meaningful
    /// metadata remain part of the comparison; unencodable pairs never collapse.
    package static func exchangeKey(
        call: [String: Any],
        output: [String: Any]
    ) -> Data? {
        let occurrenceKeys: Set<String> = ["id", "call_id"]
        let object = [
            "call": call.filter { !occurrenceKeys.contains($0.key) },
            "output": output.filter { !occurrenceKeys.contains($0.key) },
        ]
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
