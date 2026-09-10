import AsyncHTTPClient
import NIOCore

package actor ShutdownOnceUpstreamTransport: UpstreamTransport {
    private let upstream: any UpstreamTransport
    private var shutdownTask: Task<Void, any Swift.Error>?

    package init(upstream: any UpstreamTransport) {
        self.upstream = upstream
    }

    package func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        try await upstream.execute(request)
    }

    package func execute(
        _ request: HTTPClientRequest,
        timeout: TimeAmount
    ) async throws -> HTTPClientResponse {
        try await upstream.execute(request, timeout: timeout)
    }

    package func shutdown() async throws {
        let task: Task<Void, any Swift.Error>
        if let shutdownTask {
            task = shutdownTask
        } else {
            let upstream = self.upstream
            task = Task {
                try await upstream.shutdown()
            }
            shutdownTask = task
        }
        try await task.value
    }
}
