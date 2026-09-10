import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Monitoring URLSession adapter")
struct MonitoringHTTPClientTests {
    @Test("Requests reach an isolated loopback receiver and preserve the full response")
    func exchange() async throws {
        try await MonitoringHTTPServer.withServer(
            reply: .http(status: 201, headers: ["Content-Type": "application/json"], body: #"{"ok":true}"#)
        ) { server in
            var request = URLRequest(url: try await server.endpoint(), timeoutInterval: 2)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{}".utf8)
            let response = try await MonitoringURLSessionClient().send(request)
            #expect(
                response
                    == MonitoringHTTPResponse(
                        status: 201, contentType: "application/json", body: Data(#"{"ok":true}"#.utf8)))
            let received = try #require(await server.requests.first)
            let text = try #require(String(data: received, encoding: .utf8))
            #expect(text.hasPrefix("POST /fixture HTTP/1.1\r\n"))
            #expect(text.lowercased().contains("content-type: application/json\r\n"))
            #expect(text.hasSuffix("\r\n\r\n{}"))
        }
    }

    @Test(
        "GET queries and POST payloads never follow redirects", arguments: ["GET", "POST"], [301, 302, 303, 307, 308])
    func redirects(method: String, status: Int) async throws {
        try await MonitoringHTTPServer.withServer(
            reply: .http(status: status, headers: ["Location": "/redirect-target"])
        ) { server in
            var request = URLRequest(url: try await server.endpoint(), timeoutInterval: 2)
            request.httpMethod = method
            if method == "POST" { request.httpBody = Data("{}".utf8) }
            do {
                _ = try await MonitoringURLSessionClient().send(request)
                Issue.record("The adapter accepted a redirect")
            } catch let error as URLError {
                #expect(error.code == .httpTooManyRedirects)
            }
            #expect(await server.requests.count == 1)
        }
    }

    @Test("Non-redirect HTTP failures remain visible to the readiness and probe policies")
    func unavailable() async throws {
        try await MonitoringHTTPServer.withServer(reply: .http(status: 503, body: "starting")) { server in
            let response = try await MonitoringURLSessionClient().send(
                URLRequest(url: server.endpoint(), timeoutInterval: 2))
            #expect(response == MonitoringHTTPResponse(status: 503, contentType: nil, body: Data("starting".utf8)))
        }
    }

    @Test("The request timeout bounds an unresponsive receiver")
    func timeout() async throws {
        try await MonitoringHTTPServer.withServer(reply: .wait) { server in
            let request = URLRequest(url: try await server.endpoint(), timeoutInterval: 0.1)
            do {
                _ = try await MonitoringURLSessionClient().send(request)
                Issue.record("The adapter accepted an unresponsive receiver")
            } catch let error as URLError {
                #expect(error.code == .timedOut)
            }
        }
    }

    @Test("Task cancellation aborts an in-flight URLSession request")
    func cancellation() async throws {
        try await MonitoringHTTPServer.withServer(reply: .wait) { server in
            let request = URLRequest(url: try await server.endpoint(), timeoutInterval: 10)
            let task = Task { try await MonitoringURLSessionClient().send(request) }
            defer { task.cancel() }
            try await server.waitUntilRequest()
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(await server.requests.count == 1)
        }
    }
}
