import Foundation

enum MonitoringQueryEvidence {
    static func metrics(_ data: Data) throws -> Bool {
        guard let results = try results(data), results.count == 1,
            let value = results[0]["value"] as? [Any], value.count > 1
        else { return false }
        return value[1] as? String == "1"
    }

    static func logs(_ data: Data) throws -> Bool {
        try results(data)?.contains { stream in
            (stream["values"] as? [[Any]])?.contains { value in
                value.count > 1 && value[1] as? String == "monitoring.test"
            } == true
        } == true
    }

    private static func results(_ data: Data) throws -> [[String: Any]]? {
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            body["status"] as? String == "success", let data = body["data"] as? [String: Any]
        else { return nil }
        return data["result"] as? [[String: Any]]
    }
}
