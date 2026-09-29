import Foundation

/// Encodes logical UTF-8 event data. LF separates data fields; raw CR cannot
/// round-trip through SSE line parsing and is rejected before framing.
package enum ServerSentEventEncoder {
    package enum Error: Swift.Error, Equatable {
        case invalidData
    }

    package static func encode(data: Data) throws -> Data {
        guard isRepresentable(data) else { throw Error.invalidData }
        var result = dataLines(data, separatedBy: Data([0x0A]))
        result.append(contentsOf: [0x0A, 0x0A])
        return result
    }

    static func isRepresentable(_ data: Data) -> Bool {
        String(data: data, encoding: .utf8) != nil && !data.contains(0x0D)
    }

    /// The caller validates logical data before selecting its wire separator.
    static func dataLines(_ data: Data, separatedBy separator: Data) -> Data {
        var result = Data()
        for (index, line) in data.split(separator: 0x0A, omittingEmptySubsequences: false).enumerated() {
            if index > 0 { result.append(separator) }
            result.append(contentsOf: "data: ".utf8)
            result.append(line)
        }
        return result
    }
}
