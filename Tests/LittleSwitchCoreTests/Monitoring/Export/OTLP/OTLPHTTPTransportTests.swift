import Foundation
import Hummingbird
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Dedicated OTLP HTTP transport")
struct OTLPHTTPTransportTests {
    @Test("The session has no shared cookies, credentials or cache")
    func configuration() {
        let configuration = OTLPHTTPTransport.sessionConfiguration()
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(!configuration.httpShouldSetCookies)
        #expect(!configuration.waitsForConnectivity)
        #expect(configuration.timeoutIntervalForRequest == 5)
        #expect(configuration.timeoutIntervalForResource == 5)
    }

    @Test("POST preserves the exact path and never stores response cookies")
    func exactRequest() async throws {
        let router = Router()
        router.post("/custom/receiver") { request, _ in
            #expect(request.headers[.contentType] == "application/json")
            #expect(request.headers[.accept] == "application/json")
            #expect(request.headers[.authorization] == "Bearer synthetic-token")
            #expect(request.headers[.cookie] == nil)
            let body = try await request.body.collect(upTo: 100)
            #expect(String(buffer: body) == "{}")
            return Response(
                status: .ok,
                headers: [.contentType: "application/json", .setCookie: "secret=synthetic"],
                body: .init(byteBuffer: .init(string: "{}")))
        }
        try await Application(router: router).test(.live) { client in
            let transport = OTLPHTTPTransport()
            let port = try #require(client.port)
            let endpoint = try #require(URL(string: "http://localhost:\(port)/custom/receiver"))
            for _ in 0..<2 {
                let result = try await transport.send(to: endpoint, body: Data("{}".utf8), bearer: "synthetic-token")
                #expect(result.status == 200)
                #expect(result.body == Data("{}".utf8))
            }
            await transport.shutdown()
        }
    }

    @Test("Redirects are returned without forwarding credentials")
    func redirects() async throws {
        let router = Router()
        router.post("/redirect") { _, _ in
            Response(status: .temporaryRedirect, headers: [.location: "/target"])
        }
        router.post("/target") { _, _ in
            Issue.record("An OTLP redirect must never be followed")
            return Response(status: .ok)
        }
        try await Application(router: router).test(.live) { client in
            let transport = OTLPHTTPTransport()
            let port = try #require(client.port)
            let endpoint = try #require(URL(string: "http://localhost:\(port)/redirect"))
            let result = try await transport.send(to: endpoint, body: Data(), bearer: "synthetic-token")
            #expect(result.status == 307)
            await transport.shutdown()
        }
    }

    @Test("The response byte limit is enforced while reading")
    func boundedResponse() async throws {
        let router = Router()
        router.post("/large") { _, _ in
            Response(status: .ok, body: .init(byteBuffer: .init(repeating: 65, count: 1_000)))
        }
        try await Application(router: router).test(.live) { client in
            let transport = OTLPHTTPTransport(maximumResponseBytes: 64)
            let port = try #require(client.port)
            let endpoint = try #require(URL(string: "http://localhost:\(port)/large"))
            await #expect(throws: OTLPHTTPTransport.Failure.responseTooLarge) {
                _ = try await transport.send(to: endpoint, body: Data(), bearer: nil)
            }
            await transport.shutdown()
        }
    }

    @Test("A total deadline also bounds a slowly arriving response")
    func totalDeadline() async throws {
        let router = Router()
        router.post("/slow") { _, _ in
            Response(
                status: .ok,
                body: .init { writer in
                    for _ in 0..<20 {
                        try await writer.write(.init(string: " "))
                        try await Task.sleep(for: .milliseconds(20))
                    }
                    try await writer.finish(nil)
                })
        }
        try await Application(router: router).test(.live) { client in
            let transport = OTLPHTTPTransport(deadline: .milliseconds(60))
            let port = try #require(client.port)
            let endpoint = try #require(URL(string: "http://localhost:\(port)/slow"))
            await #expect(throws: OTLPHTTPTransport.Failure.deadline) {
                _ = try await transport.send(to: endpoint, body: Data(), bearer: nil)
            }
            await transport.shutdown()
        }
    }
}
