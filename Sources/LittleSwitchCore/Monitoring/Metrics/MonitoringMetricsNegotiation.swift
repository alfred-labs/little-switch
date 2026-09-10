import Foundation

enum MonitoringMetricsNegotiation {
    private struct MediaRange {
        let media: String
        let version: String?
        let parameterSpecificity: Int
        let quality: Double

        init?(_ text: Substring) {
            let fields = text.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            guard let media = fields.first else { return nil }
            var parameters: [String: String] = [:]
            for field in fields.dropFirst() {
                let pair = field.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard pair.count == 2, parameters[pair[0]] == nil else { return nil }
                parameters[pair[0]] = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
            guard parameters["charset"] == nil || parameters["charset"] == "utf-8" else { return nil }
            let rawQuality = parameters["q"] ?? "1"
            let pattern = #"^(?:0(?:\.[0-9]{0,3})?|1(?:\.0{0,3})?)$"#
            guard rawQuality.range(of: pattern, options: .regularExpression) != nil, let quality = Double(rawQuality)
            else { return nil }
            self.media = media
            self.version = parameters["version"]
            self.parameterSpecificity = ["version", "charset"].filter { parameters[$0] != nil }.count
            self.quality = quality
        }

        var prometheusSpecificity: Int? {
            guard version == nil || version == "0.0.4" else { return nil }
            switch media {
            case "text/plain": return 6 + parameterSpecificity
            case "text/*": return 3 + parameterSpecificity
            case "*/*": return parameterSpecificity
            default: return nil
            }
        }

        var openMetricsSpecificity: Int? {
            guard media == "application/openmetrics-text", version == nil || version == "1.0.0" else { return nil }
            return 6 + parameterSpecificity
        }
    }

    static func resolve(_ headers: [String]) -> MonitoringMetricsFormat? {
        guard !headers.isEmpty else { return .prometheus }
        let ranges = headers.flatMap { $0.split(separator: ",") }.compactMap(MediaRange.init)
        let prometheus = quality(ranges, specificity: \.prometheusSpecificity)
        let openMetrics = quality(ranges, specificity: \.openMetricsSpecificity)
        if openMetrics > prometheus { return .openMetrics }
        if prometheus > 0 { return .prometheus }
        return nil
    }

    private static func quality(_ ranges: [MediaRange], specificity: KeyPath<MediaRange, Int?>) -> Double {
        let matches = ranges.compactMap { range in range[keyPath: specificity].map { ($0, range.quality) } }
        guard let bestSpecificity = matches.map(\.0).max() else { return 0 }
        return matches.filter { $0.0 == bestSpecificity }.reduce(0) { max($0, $1.1) }
    }
}
