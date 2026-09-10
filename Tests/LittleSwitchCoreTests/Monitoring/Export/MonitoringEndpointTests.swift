import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring endpoints")
struct MonitoringEndpointTests {
    @Test(
        "Valid complete destinations preserve their full URL",
        arguments: [
            "http://localhost:9090/api/v1/otlp/v1/metrics",
            "http://localhost:3100/otlp/v1/logs",
            "http://LOCALHOST:4318/v1/metrics",
            "http://127.0.0.1:4318/v1/metrics",
            "http://127.34.5.6:4318/v1/logs",
            "http://127.255.255.255:65535/v1/metrics",
            "http://[::1]:4318/v1/logs",
            "http://[0:0:0:0:0:0:0:1]:4318/v1/metrics",
            "https://collector.example.com/v1/metrics",
            "https://collector.example.com:1/v1/logs",
            "https://[2001:db8::1]:4318/v1/logs",
            "https://collector.example.com",
            "https://collector.example.com/custom/path/",
            "https://collector.example.com/a%2Fb/v1/logs",
        ]
    )
    func validEndpoints(raw: String) throws {
        #expect(try MonitoringEndpoint.validate(raw).absoluteString == raw)
    }

    @Test(
        "Remote HTTP and misleading loopback hosts are rejected without DNS resolution",
        arguments: [
            "http://example.com/v1/metrics",
            "http://localhost.example.com/v1/logs",
            "http://localhost./v1/logs",
            "http://127.0.0.1.example.com/v1/logs",
            "http://127.0.0.999/v1/logs",
            "http://127.1/v1/logs",
            "http://2130706433/v1/logs",
            "http://0177.0.0.1/v1/logs",
            "http://0x7f.0.0.1/v1/logs",
            "http://126.255.255.255/v1/logs",
            "http://128.0.0.0/v1/logs",
            "http://0.0.0.0/v1/logs",
            "http://192.168.1.1/v1/logs",
            "http://[::]/v1/logs",
            "http://[::2]/v1/logs",
            "http://[2001:db8::1]/v1/logs",
            "http://[::ffff:127.0.0.1]/v1/logs",
            "http://[::1%25lo0]/v1/logs",
        ]
    )
    func insecureRemoteEndpoints(raw: String) {
        #expect(throws: MonitoringEndpoint.Error.insecureRemoteHTTP) {
            try MonitoringEndpoint.validate(raw)
        }
    }

    @Test(
        "User information, fragments and every query are forbidden",
        arguments: [
            "https://user@example.com/v1/logs",
            "https://user:password@example.com/v1/logs",
            "https://us%65r:p%40ss@example.com/v1/logs",
            "https://@example.com/v1/logs",
            "https://example.com/v1/logs#fragment",
            "https://example.com/v1/logs#",
            "https://example.com/v1/logs?token=value",
            "https://example.com/v1/logs?",
            "https://example.com/v1/logs?harmless=value",
        ]
    )
    func forbiddenComponents(raw: String) {
        #expect(throws: MonitoringEndpoint.Error.forbiddenComponent) {
            try MonitoringEndpoint.validate(raw)
        }
    }

    @Test(
        "Malformed endpoints, invalid ports and literal whitespace are rejected",
        arguments: [
            "",
            "/v1/logs",
            "//example.com/v1/logs",
            "https:///v1/logs",
            "https://",
            "https:receiver.example/v1/logs",
            "https://:4318/v1/logs",
            "https://example.com:0/v1/logs",
            "https://example.com:65536/v1/logs",
            "https://example.com:-1/v1/logs",
            "https://example.com:abc/v1/logs",
            "https://example.com:/v1/logs",
            "https://example.com:999999999999999999999999/v1/logs",
            "https://[::1]:0/v1/logs",
            " https://example.com/v1/logs",
            "https://example.com/v1/logs ",
            "https://example.com/a b",
            "https://example.com/a\tb",
            "https://example.com/a\nb",
            "https://example.com/a\u{0000}b",
            "https://example.com/a\u{007F}b",
            "https://example.com/a\u{00A0}b",
            "https://example.com/%not-encoded",
        ]
    )
    func invalidEndpoints(raw: String) {
        #expect(throws: MonitoringEndpoint.Error.invalidURL) {
            try MonitoringEndpoint.validate(raw)
        }
    }

    @Test(
        "Non-HTTP schemes are not export destinations",
        arguments: [
            "ftp://example.com/v1/logs",
            "file:///tmp/logs",
            "ws://localhost:4318/v1/logs",
            "httpss://example.com/v1/logs",
        ]
    )
    func unsupportedSchemes(raw: String) {
        #expect(throws: MonitoringEndpoint.Error.unsupportedScheme) {
            try MonitoringEndpoint.validate(raw)
        }
    }
}
