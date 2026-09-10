import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("MCP accepts only UTF-8 encoded JSON")
    func webSearchMCPRejectsOtherEncodings() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let app = makeApplication(fixture: fixture, transport: transport)
        let ping = #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#
        let encodings: [String.Encoding] = [.utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian]
        let encoded = try encodings.map { try #require(ping.data(using: $0)) }
        let bodies = encoded + [Data([0xFF]), Data([0]) + Data(ping.utf8)]
        try await app.test(.router) { client in
            for body in bodies {
                let result = try await client.execute(
                    uri: "/api/mcp",
                    method: .post,
                    headers: webSearchMCPHeaders,
                    body: ByteBuffer(bytes: body)
                )
                #expect(result.status == .badRequest)
                #expect(
                    try mcpJSONEqual(
                        data(result.body), #"{"jsonrpc":"2.0","error":{"code":-32700,"message":"Parse error"}}"#))
            }
            #expect(await transport.requests.isEmpty)
        }
    }

    @Test("MCP rejects malformed envelopes before search execution")
    func webSearchMCPInvalidRequests() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let app = makeApplication(fixture: fixture, transport: transport)
        let cases = [
            ("not json", -32_700),
            ("[]", -32_600),
            ("null", -32_600),
            (#"{"jsonrpc":"2.0","id":null,"method":"ping"}"#, -32_600),
            (#"{"jsonrpc":"2.0","id":true,"method":"ping"}"#, -32_600),
            (#"{"jsonrpc":"2.0","id":1.5,"method":"ping"}"#, -32_600),
            (#"{"jsonrpc":"2.0","id":[],"method":"ping"}"#, -32_600),
        ]
        try await app.test(.router) { client in
            for (body, code) in cases {
                let result = try await client.execute(
                    uri: "/api/mcp",
                    method: .post,
                    headers: webSearchMCPHeaders,
                    body: ByteBuffer(string: body)
                )
                #expect(result.status == .badRequest)
                let object = try anthropicObject(data(result.body))
                #expect(object["id"] == nil)
                let error = try #require(object["error"] as? [String: Any])
                #expect(error["code"] as? Int == code)
            }
            #expect(await transport.requests.isEmpty)
        }
    }

    @Test("MCP errors preserve readable IDs even when the envelope is invalid")
    func webSearchMCPInvalidEnvelopeWithID() async throws {
        let fixture = try makeFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let app = makeApplication(fixture: fixture, transport: transport)
        let bodies = [
            #"{"jsonrpc":"1.0","id":1,"method":"ping"}"#,
            #"{"jsonrpc":"2.0","id":1,"result":{}}"#,
            #"{"jsonrpc":"2.0","id":1,"method":"ping","params":[]}"#,
        ]
        try await app.test(.router) { client in
            for body in bodies {
                let result = try await client.execute(
                    uri: "/api/mcp",
                    method: .post,
                    headers: webSearchMCPHeaders,
                    body: ByteBuffer(string: body)
                )
                #expect(result.status == .badRequest)
                #expect(
                    try mcpJSONEqual(
                        data(result.body),
                        #"{"jsonrpc":"2.0","id":1,"error":{"code":-32600,"message":"Invalid request"}}"#))
            }
            #expect(await transport.requests.isEmpty)
        }
    }

    @Test("MCP reports unsupported methods and invalid tool arguments with the request ID")
    func webSearchMCPInvalidOperations() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let app = makeApplication(fixture: fixture, transport: transport)
        let cases = [
            (#""method":"missing""#, -32_601),
            (#""method":"initialize","params":{}"#, -32_602),
            (#""method":"tools/call""#, -32_602),
            (#""method":"tools/call","params":{"name":"missing","arguments":{"query":"Swift"}}"#, -32_602),
            (#""method":"tools/call","params":{"name":"web_search"}"#, -32_602),
            (#""method":"tools/call","params":{"name":"web_search","arguments":{"query":42}}"#, -32_602),
            (#""method":"tools/call","params":{"name":"web_search","arguments":{"query":" \n "}}"#, -32_602),
            (
                #""method":"tools/call","params":{"name":"web_search","arguments":{"query":"Swift","extra":true}}"#,
                -32_602
            ),
            (#""method":"tools/list","params":{"cursor":"unknown"}"#, -32_602),
        ]
        try await app.test(.router) { client in
            for (operation, code) in cases {
                let result = try await client.execute(
                    uri: "/api/mcp",
                    method: .post,
                    headers: webSearchMCPHeaders,
                    body: ByteBuffer(string: #"{"jsonrpc":"2.0","id":"request",\#(operation)}"#)
                )
                #expect(result.status == .ok)
                let object = try anthropicObject(data(result.body))
                #expect(object["id"] as? String == "request")
                let error = try #require(object["error"] as? [String: Any])
                #expect(error["code"] as? Int == code)
            }
            #expect(await transport.requests.isEmpty)
        }
    }

    @Test("MCP enforces media types, protocol version, origin and body bounds")
    func webSearchMCPHTTPBoundaries() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let app = makeApplication(fixture: fixture, transport: transport, maximumRequestBytes: 512)
        let versionHeader = try #require(HTTPField.Name("MCP-Protocol-Version"))
        var wrongVersion = webSearchMCPHeaders
        wrongVersion[versionHeader] = "unknown"
        var olderVersion = webSearchMCPHeaders
        olderVersion[versionHeader] = "2025-03-26"
        var duplicateContentType = webSearchMCPHeaders
        duplicateContentType[.contentType] = "application/json;charset=utf-8"
        duplicateContentType.append(HTTPField(name: .contentType, value: "text/plain"))
        var origin = webSearchMCPHeaders
        origin[.origin] = "https://example.com"
        let cases: [(HTTPFields, HTTPResponse.Status)] = [
            ([.contentType: "text/plain", .accept: "application/json, text/event-stream"], .unsupportedMediaType),
            ([.contentType: "application/json", .accept: "text/event-stream"], .notAcceptable),
            ([.contentType: "application/json", .accept: "application/json;q=0, text/event-stream"], .notAcceptable),
            (wrongVersion, .badRequest),
            (olderVersion, .badRequest),
            (duplicateContentType, .unsupportedMediaType),
            (origin, .forbidden),
        ]
        try await app.test(.router) { client in
            for (headers, status) in cases {
                let result = try await client.execute(
                    uri: "/api/mcp",
                    method: .post,
                    headers: headers,
                    body: ByteBuffer(string: webSearchMCPCall)
                )
                #expect(result.status == status)
            }
            let large = try await client.execute(
                uri: "/api/mcp",
                method: .post,
                headers: webSearchMCPHeaders,
                body: ByteBuffer(string: String(repeating: " ", count: 513))
            )
            #expect(large.status == .contentTooLarge)
            for method in [HTTPRequest.Method.get, .delete] {
                let result = try await client.execute(uri: "/api/mcp", method: method)
                #expect(result.status == .methodNotAllowed)
                #expect(result.headers[.allow] == "POST")
            }
            #expect(await transport.requests.isEmpty)
        }
    }
}
