import Foundation

/// Only protocol discriminators survive decoding; remote error text is ignored.
struct MonitoringProviderFailureEnvelope: Decodable {
    private enum CodingKeys: String, CodingKey { case type, error, message, response }

    private struct ObjectPresence: Decodable {
        init(from decoder: any Decoder) throws {
            _ = try decoder.container(keyedBy: CodingKeys.self)
        }
    }

    private struct Response: Decodable {
        let status: String?
    }

    private struct StringPresence: Decodable {
        init(from decoder: any Decoder) throws {
            _ = try decoder.singleValueContainer().decode(String.self)
        }
    }

    private let type: String?
    private let error: ObjectPresence?
    private let message: StringPresence?
    private let response: Response?

    var isError: Bool { type == "error" && (error != nil || message != nil) }
    var isFailedResponse: Bool { type == "response.failed" && response?.status == "failed" }
    var isFailure: Bool { isError || isFailedResponse }

    static func decode(frame: Data) -> Self? {
        guard let text = String(bytes: frame, encoding: .utf8) else { return nil }
        let values = text.split(separator: "\n").compactMap { line -> Substring? in
            guard line.hasPrefix("data:") else { return nil }
            let value = line.dropFirst(5)
            return value.first == " " ? value.dropFirst() : value
        }
        let data = Data(values.joined(separator: "\n").utf8)
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}
