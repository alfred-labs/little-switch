import LittleSwitchCommon

/// Response snapshots are cumulative, but automatic steering successors are
/// distinct billable generations. IDs are scoped to this provider body only.
struct MonitoringUsageLedger: Sendable {
    private var anonymous: GatewayUsageTotals?
    private(set) var responses: [String: GatewayUsageTotals] = [:]

    var totals: GatewayUsageTotals? {
        guard anonymous != nil || !responses.isEmpty else { return nil }
        return responses.values.reduce(anonymous ?? GatewayUsageTotals(), +)
    }

    /// A consumer may abandon a body before the enclosing response object ends.
    /// Include its complete usage as soon as its identity is known, without
    /// committing an unidentified sample that could later prove a duplicate.
    func totals(including measurement: GatewayUsageTotals?, responseID: String?) -> GatewayUsageTotals? {
        guard let measurement, let responseID,
            responses[responseID] != nil || responses.count < 128
        else { return totals }
        var result = anonymous ?? GatewayUsageTotals()
        for (identifier, usage) in responses {
            result += identifier == responseID ? usage.merging(measurement) : usage
        }
        if responses[responseID] == nil { result += measurement }
        return result
    }

    /// The same bound as the request context's provider-exchange accounting.
    mutating func record(_ measurement: GatewayUsageTotals, responseID: String?) -> Bool {
        guard let responseID else {
            anonymous = anonymous?.merging(measurement) ?? measurement
            return true
        }
        guard responses[responseID] != nil || responses.count < 128 else { return false }
        responses[responseID] = responses[responseID]?.merging(measurement) ?? measurement
        return true
    }
}
