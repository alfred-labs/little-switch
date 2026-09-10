import Foundation

package struct MonitoringProbe: Sendable {
    private let client: any MonitoringHTTPClient
    private let sleep: MonitoringSleep

    package init(client: any MonitoringHTTPClient, sleep: @escaping MonitoringSleep) {
        self.client = client
        self.sleep = sleep
    }

    package func run(id: UUID, unixMilliseconds: Int64, emit: MonitoringOutput) async throws {
        let requests = try MonitoringProbeRequests(id: id, unixMilliseconds: unixMilliseconds)
        for request in [requests.metrics, requests.logs] {
            try Task.checkCancellation()
            let response = try await client.send(request)
            await emit(try receipt(request: request, response: response))
            guard (200..<300).contains(response.status) else { throw MonitoringFailure.rejectedPayload }
        }
        try await eventually(requests.metricsQuery, satisfies: MonitoringQueryEvidence.metrics)
        try await eventually(requests.logsQuery, satisfies: MonitoringQueryEvidence.logs)
        await emit("OTLP JSON metrics and logs are queryable")
    }

    private func eventually(
        _ request: URLRequest, satisfies: @Sendable (Data) throws -> Bool
    ) async throws {
        for _ in 0..<30 {
            try Task.checkCancellation()
            let response = try await client.send(request)
            let matches = try satisfies(response.body)
            if (200..<300).contains(response.status), matches { return }
            try await sleep(.seconds(1))
        }
        throw MonitoringFailure.notQueryable
    }

    package func receipt(request: URLRequest, response: MonitoringHTTPResponse) throws -> String {
        // Match fetch.text(): receiver diagnostics repair malformed UTF-8 rather than dropping the reply.
        // swift-format-ignore: UseStringIfEncodingDecoding
        // swiftlint:disable:next optional_data_string_conversion
        let reply = String(decoding: response.body, as: UTF8.self)
        let object: [String: Any] = [
            "endpoint": request.url?.path ?? "",
            "status": response.status,
            "contentType": response.contentType.map { $0 as Any } ?? NSNull(),
            "reply": reply,
        ]
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        // JSONSerialization always produces valid UTF-8.
        // swift-format-ignore: UseStringIfEncodingDecoding
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: bytes, as: UTF8.self)
    }
}
