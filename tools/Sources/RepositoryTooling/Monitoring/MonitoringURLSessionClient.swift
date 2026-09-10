import Foundation

/// Blocks all redirects so the readiness and probe policies see the exact
/// status code the receiver returned, never a followed location.
private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
    // swiftlint:disable:next multiline_parameters
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

package final class MonitoringURLSessionClient: MonitoringHTTPClient, Sendable {
    private let session: URLSession

    package init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let delegate = RedirectBlocker()
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    deinit { session.finishTasksAndInvalidate() }

    package func send(_ request: URLRequest) async throws -> MonitoringHTTPResponse {
        try Task.checkCancellation()
        do {
            let (body, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard ![301, 302, 303, 307, 308].contains(http.statusCode) else {
                throw URLError(.httpTooManyRedirects)
            }
            return MonitoringHTTPResponse(
                status: http.statusCode, contentType: http.value(forHTTPHeaderField: "Content-Type"), body: body)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }
    }
}
