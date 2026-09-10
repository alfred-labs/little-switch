import Foundation
import Testing

@testable import RepositoryTooling

actor MonitoringFixture: MonitoringHTTPClient {
    enum Action: Sendable {
        case response(Int, String = "", String? = nil)
        case unavailable
        case cancelled
    }

    enum Failure: Error { case unavailable, unexpectedRequest }

    private var actions: [Action]
    private(set) var requests: [URLRequest] = []
    private(set) var sleeps: [Duration] = []
    private(set) var output: [String] = []
    var cancelSleep = false

    init(_ actions: [Action]) { self.actions = actions }

    func send(_ request: URLRequest) throws -> MonitoringHTTPResponse {
        requests.append(request)
        guard !actions.isEmpty else { throw Failure.unexpectedRequest }
        switch actions.removeFirst() {
        // swiftlint:disable:next pattern_matching_keywords
        case .response(let status, let body, let contentType):
            return MonitoringHTTPResponse(status: status, contentType: contentType, body: Data(body.utf8))
        case .unavailable: throw Failure.unavailable
        case .cancelled: throw CancellationError()
        }
    }

    func sleep(_ duration: Duration) async throws {
        sleeps.append(duration)
        if cancelSleep { throw CancellationError() }
    }

    func emit(_ line: String) async { output.append(line) }

    func cancelDuringSleep() { cancelSleep = true }
}
