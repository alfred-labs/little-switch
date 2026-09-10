import Foundation

/// A private session for observability: provider requests never wait on this transport.
package final class OTLPHTTPTransport: OTLPTransporting {
    package enum Failure: Error, Equatable, Sendable {
        case responseTooLarge
        case invalidResponse
        case invalidCredential
        case deadline
    }

    private let session: URLSession
    private let deadline: Duration
    private let maximumResponseBytes: Int

    package init(deadline: Duration = .seconds(5), maximumResponseBytes: Int = 1_048_576) {
        self.deadline = deadline
        self.maximumResponseBytes = max(0, maximumResponseBytes)
        session = URLSession(configuration: Self.sessionConfiguration())
    }

    package static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        return configuration
    }

    package func send(to endpoint: URL, body: Data, bearer: String?) async throws -> OTLPHTTPResponse {
        try Task.checkCancellation()
        let validated = try MonitoringEndpoint.validate(endpoint.absoluteString)
        var request = URLRequest(url: validated)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearer {
            guard !bearer.isEmpty, bearer.utf8.allSatisfy({ (33...126).contains($0) }) else {
                throw Failure.invalidCredential
            }
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        let outgoing = request
        let outcome = await withTaskGroup(of: Result<OTLPHTTPResponse, any Error>.self) { group in
            group.addTask {
                do { return .success(try await self.receive(outgoing)) } catch { return .failure(error) }
            }
            group.addTask {
                do { try await Task.sleep(for: self.deadline) } catch { return .failure(error) }
                return .failure(Failure.deadline)
            }
            var first: Result<OTLPHTTPResponse, any Error> = .failure(CancellationError())
            for await result in group {
                first = result
                break
            }
            group.cancelAll()
            return first
        }
        return try outcome.get()
    }

    private func receive(_ request: URLRequest) async throws -> OTLPHTTPResponse {
        let (bytes, response) = try await session.bytes(for: request, delegate: OTLPRedirectBlocker())
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        var body = Data()
        body.reserveCapacity(min(maximumResponseBytes, 16_384))
        for try await byte in bytes {
            try Task.checkCancellation()
            guard body.count < maximumResponseBytes else { throw Failure.responseTooLarge }
            body.append(byte)
        }
        return OTLPHTTPResponse(
            status: response.statusCode,
            contentType: response.value(forHTTPHeaderField: "Content-Type"),
            retryAfter: response.value(forHTTPHeaderField: "Retry-After"),
            body: body
        )
    }

    package func shutdown() async {
        session.invalidateAndCancel()
    }
}

private final class OTLPRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
