import Foundation
import Testing

@testable import LittleSwitchTransport

@Suite("Endpoint URL validation")
struct EndpointURLTests {
    @Test("Localhost HTTP is accepted")
    func localhostAccepted() throws {
        #expect(try EndpointURL.normalize("http://localhost/api") == "http://localhost/api")
    }

    @Test("IPv4 loopback HTTP is accepted")
    func ipv4LoopbackAccepted() throws {
        #expect(try EndpointURL.normalize("http://127.0.0.1/api") == "http://127.0.0.1/api")
        #expect(try EndpointURL.normalize("http://127.0.0.1:8080/api") == "http://127.0.0.1:8080/api")
        #expect(try EndpointURL.normalize("http://127.1.2.3/api") == "http://127.1.2.3/api")
    }

    @Test("IPv6 loopback HTTP is accepted")
    func ipv6LoopbackAccepted() throws {
        #expect(try EndpointURL.normalize("http://[::1]/api") == "http://[::1]/api")
    }

    @Test("A DNS name beginning with 127. is rejected as insecure remote HTTP")
    func spoofedLoopbackRejected() {
        #expect(throws: EndpointURL.Error.insecureRemoteHTTP) {
            try EndpointURL.normalize("http://127.example.com/api")
        }
    }

    @Test("Non-loopback addresses remain rejected for plain HTTP")
    func remoteHTTPRejected() {
        #expect(throws: EndpointURL.Error.insecureRemoteHTTP) {
            try EndpointURL.normalize("http://example.com/api")
        }
        #expect(throws: EndpointURL.Error.insecureRemoteHTTP) {
            try EndpointURL.normalize("http://192.168.1.1/api")
        }
    }

    @Test("Malformed pseudo-IPv4 loopback forms are rejected")
    func malformedLoopbackRejected() {
        #expect(throws: EndpointURL.Error.insecureRemoteHTTP) {
            try EndpointURL.normalize("http://127.0.0/api")
        }
        #expect(throws: EndpointURL.Error.insecureRemoteHTTP) {
            try EndpointURL.normalize("http://127.0.0.256/api")
        }
        #expect(throws: EndpointURL.Error.insecureRemoteHTTP) {
            try EndpointURL.normalize("http://0127.0.0.1/api")
        }
    }

    @Test("HTTPS is accepted regardless of host")
    func httpsAccepted() throws {
        #expect(try EndpointURL.normalize("https://example.com/api") == "https://example.com/api")
        #expect(try EndpointURL.normalize("https://127.example.com/api") == "https://127.example.com/api")
    }
}
