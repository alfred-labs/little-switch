import AsyncHTTPClient
import HTTPTypes
import HummingbirdTesting
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

struct ChatGPTGatewayCookieTests {
    @Test func deviceRegistrationScopesOfficialCookiesToTheLocalHost() async throws {
        let transport = RecordingGatewayTransport(responses: [
            HTTPClientResponse(
                status: .ok,
                headers: HTTPHeaders([
                    ("set-cookie", "_devicecheck=synthetic-token; Domain=.chatgpt.com; Path=/; Secure; SameSite=Lax"),
                    (
                        "set-cookie",
                        "session=synthetic-session; Domain=chatgpt.com; Path=/backend-api; HttpOnly; Secure"
                    ),
                    ("content-type", "application/json"),
                ]),
                body: .bytes(ByteBuffer(string: "{}"))
            )
        ])
        try await chatGPTApplication(fixture: chatGPTGatewayFixture(), transport: transport).test(.router) { client in
            let response = try await client.execute(uri: "/backend-api/devicecheck", method: .post)
            #expect(response.status == .ok)
            #expect(String(buffer: response.body) == "{}")
            #expect(
                response.headers[values: .setCookie] == [
                    "_devicecheck=synthetic-token; Path=/; Secure; SameSite=Lax",
                    "session=synthetic-session; Path=/backend-api; HttpOnly; Secure",
                ])
        }
    }

    @Test(arguments: [
        (
            "token=value; dOmAiN= .CHATGPT.COM \t; Secure; HttpOnly; SameSite=None; Partitioned",
            "token=value; Secure; HttpOnly; SameSite=None; Partitioned"
        ),
        (
            "token=; Domain=chatgpt.com; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/; Secure",
            "token=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/; Secure"
        ),
        ("token=value; Domain=chatgpt.com; Domain=.CHATGPT.COM; Secure", "token=value; Secure"),
        ("Domain=opaque==; Path=/; Secure; HttpOnly", "Domain=opaque==; Path=/; Secure; HttpOnly"),
        ("__Host-token=opaque; Path=/; Secure; HttpOnly", "__Host-token=opaque; Path=/; Secure; HttpOnly"),
        (
            "token=\"opaque==\"; Path=/; X-Domain=untouched; Priority=High; Secure;",
            "token=\"opaque==\"; Path=/; X-Domain=untouched; Priority=High; Secure;"
        ),
    ])
    func preservesCookieValuesAndEveryNonDomainAttribute(upstream: String, local: String) async throws {
        try await assertNativeCookies([upstream], equal: [local])
    }

    @Test(arguments: [
        "token=value; Domain=localhost; Secure",
        "token=value; Domain=other.invalid; Secure",
        "token=value; Domain=chatgpt.com.evil.invalid; Secure",
        "token=value; Domain=sub.chatgpt.com; Secure",
        "token=value; Domain=com; Secure",
        "token=value; Domain=..chatgpt.com; Secure",
        "token=value; Domain=chatgpt.com.; Secure",
        "token=value; Domain=; Secure",
        "token=value; Domain; Secure",
        "token=value; Domain=chatgpt.com; Domain=other.invalid; Secure",
        "token=value; Domain=other.invalid; Domain=chatgpt.com; Secure",
        "__Host-token=value; Domain=chatgpt.com; Path=/; Secure",
        "__host-token=value; Domain=.chatgpt.com; Path=/; Secure",
    ])
    func neverMakesAnInvalidUpstreamDomainOrHostPrefixValidLocally(upstream: String) async throws {
        try await assertNativeCookies([upstream], equal: [])
    }

    @Test func mergedCatalogPreservesCookieRenewal() async throws {
        let transport = RecordingGatewayTransport(responses: [
            HTTPClientResponse(
                status: .ok,
                headers: ["set-cookie": "_devicecheck=renewed; Domain=.chatgpt.com; Path=/; Secure; SameSite=Lax"],
                body: .bytes(ByteBuffer(string: #"{"models":[{"slug":"native","title":"Native"}]}"#))
            )
        ])
        try await chatGPTApplication(fixture: chatGPTGatewayFixture(), transport: transport).test(.router) { client in
            let response = try await client.execute(uri: "/backend-api/models", method: .get)
            #expect(response.status == .ok)
            #expect(response.headers[values: .setCookie] == ["_devicecheck=renewed; Path=/; Secure; SameSite=Lax"])
            #expect(String(buffer: response.body).contains("example:chat-model"))
        }
    }

    private func assertNativeCookies(_ upstream: [String], equal expected: [String]) async throws {
        let transport = RecordingGatewayTransport(responses: [
            HTTPClientResponse(status: .unauthorized, headers: HTTPHeaders(upstream.map { ("set-cookie", $0) }))
        ])
        try await chatGPTApplication(fixture: chatGPTGatewayFixture(), transport: transport).test(.router) { client in
            let response = try await client.execute(uri: "/backend-api/devicecheck", method: .post)
            #expect(response.status == .unauthorized)
            #expect(response.headers[values: .setCookie] == expected)
        }
    }
}
