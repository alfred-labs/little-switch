import Foundation

package struct SessionToolDefinitions {
    package struct Summary: Equatable, Sendable {
        package let model: String
        package var requests: Int
        package var maximumDefinitions: Int
        package var lastDefinitions: Int
        package var usesToolSearch: Bool
    }

    private var positions: [String: Int] = [:]
    private var groups: [Summary] = []

    package init() {}

    package mutating func ingest(_ line: Data) {
        guard let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let action = entry["action"] as? [String: Any],
            let request = action["claudeRequestBody"] as? [String: Any],
            let encoded = request["_0"] as? String,
            let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters)
        else { return }
        // Match the diagnostic's existing UTF-8 replacement semantics; no body is printed.
        // swiftlint:disable:next optional_data_string_conversion
        let repaired = Data(String(decoding: data, as: UTF8.self).utf8)
        guard let body = try? DiagnosticJSONReader.read(repaired),
            let first = body["messages"]?.elements?.first
        else { return }
        let canonical = DiagnosticMessagePrefix.encode(first)
        let names = (body["tools"]?.elements ?? []).compactMap { tool -> String? in
            guard case .object = tool else { return nil }
            return tool["name"]?.text ?? ""
        }
        let model = body["model"]?.text ?? "?"
        let builtins = names.filter { !$0.utf8.starts(with: "mcp__".utf8) }
        let sorted = builtins.sorted {
            $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars)
        }
        // An ASCII JSON tuple preserves field boundaries and Unicode scalar identity.
        let prefix = DiagnosticJSON.string(String(canonical.prefix(400)))
        let keys = [DiagnosticJSON.string(model), prefix, DiagnosticJSON.array(sorted.map(DiagnosticJSON.string))]
        let key = DiagnosticMessagePrefix.encode(.array(keys))
        let count = names.filter { $0.utf8.starts(with: "mcp__".utf8) }.count
        let position: Int
        if let existing = positions[key] {
            position = existing
        } else {
            position = groups.count
            positions[key] = position
            groups.append(
                Summary(model: model, requests: 0, maximumDefinitions: 0, lastDefinitions: 0, usesToolSearch: false)
            )
        }
        groups[position].requests += 1
        groups[position].maximumDefinitions = max(groups[position].maximumDefinitions, count)
        groups[position].lastDefinitions = count
        groups[position].usesToolSearch = groups[position].usesToolSearch || names.contains("ToolSearch")
    }

    package var summaries: [Summary] {
        let sorted = groups.enumerated().sorted {
            if $0.element.requests == $1.element.requests { return $0.offset < $1.offset }
            return $0.element.requests > $1.element.requests
        }
        return sorted.map(\.element)
    }

    package func report(mounted: Int? = nil) -> String {
        guard !groups.isEmpty else { return "no sessions found\n" }
        var lines = [header]
        for summary in summaries {
            let ratio = mounted.map { $0 == 0 ? "-" : "\(summary.lastDefinitions)/\($0)" } ?? "-"
            lines.append(
                self.row(
                    summary.model,
                    requests: String(summary.requests),
                    search: summary.usesToolSearch ? "oui" : "non",
                    last: String(summary.lastDefinitions),
                    maximum: String(summary.maximumDefinitions),
                    ratio: ratio))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private var header: String {
        row("model", requests: "reqs", search: "TS", last: "last_defs", maximum: "max_defs", ratio: "ratio")
    }

    // swiftlint:disable:next function_parameter_count
    private func row(
        _ model: String, requests: String, search: String, last: String, maximum: String, ratio: String
    ) -> String {
        model + padding(model, width: 24) + " " + padding(requests, width: 5) + requests + " "
            + padding(search, width: 4) + search + " " + padding(last, width: 9) + last + " "
            + padding(maximum, width: 8) + maximum + "  " + ratio
    }

    private func padding(_ value: String, width: Int) -> String {
        String(repeating: " ", count: max(0, width - value.unicodeScalars.count))
    }
}
