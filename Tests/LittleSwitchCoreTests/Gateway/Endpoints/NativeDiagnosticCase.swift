import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import NIOCore
import NIOHTTP1
import NIOHTTP2
import NIOSSL
// swift-format sorts case-sensitively; SwiftLint sorts case-insensitively.
// swiftlint:disable:next sorted_imports
import Network
import Testing

struct NativeDiagnosticCase: Sendable, CustomTestStringConvertible {
    let error: any Error
    let summary: String
    var testDescription: String { summary }
    static let privateValue = "synthetic-private-error-value"

    static var all: [Self] {
        var cases: [Self] = [
            .init(
                error: HTTPClientError.invalidHeaderFieldValues([privateValue]),
                summary: "HTTPClientError.invalidHeaderFieldValues"),
            .init(
                error: HTTPClientError.invalidHeaderFieldNames([privateValue]),
                summary: "HTTPClientError.invalidHeaderFieldNames"),
            .init(
                error: HTTPClientError.internalStateFailure(file: privateValue, line: 123),
                summary: "HTTPClientError.internalStateFailure"),
            .init(
                error: HTTPClientError.serverOfferedUnsupportedApplicationProtocol(privateValue),
                summary: "HTTPClientError.serverOfferedUnsupportedApplicationProtocol"),
            .init(
                error: URLError(
                    .cannotConnectToHost,
                    userInfo: [
                        NSLocalizedDescriptionKey: privateValue, NSURLErrorFailingURLStringErrorKey: privateValue,
                    ]), summary: "URLError(code: -1004)"),
            .init(
                error: NSError(domain: privateValue, code: 7, userInfo: [NSLocalizedDescriptionKey: privateValue]),
                summary: "NSError(code: 7)"),
            .init(error: NWError.posix(.ECONNRESET), summary: "NWError.posix(code: 54)"),
            .init(error: NWError.tls(-9_806), summary: "NWError.tls(code: -9806)"),
            .init(error: NWError.dns(-65_538), summary: "NWError.dns(code: -65538)"),
            .init(error: IOError(errnoCode: 54, reason: privateValue), summary: "IOError(errno: 54)"),
            .init(
                error: NIOHTTP2Errors.streamClosed(streamID: 3, errorCode: .cancel, file: privateValue),
                summary: "NIOHTTP2Errors.StreamClosed(code: 8)"),
            .init(
                error: NIOSSLError.handshakeFailed(.sslError([.eofDuringHandshake])),
                summary: "NIOSSLError.handshakeFailed(sslError)"),
            .init(error: NIOSSLError.uncleanShutdown, summary: "NIOSSLError.uncleanShutdown"),
            .init(
                error: NIOSSLExtraError.failedToValidateHostname,
                summary: "NIOSSLExtraError.failedToValidateHostname"),
            .init(error: ChannelError.connectTimeout(.seconds(10)), summary: "ChannelError.connectTimeout"),
            .init(
                error: UpstreamWebSocketFailure(
                    kind: .upgradeRejected,
                    response: .init(
                        head: .init(
                            version: .http1_1,
                            status: .init(statusCode: 502, reasonPhrase: privateValue),
                            headers: ["private": privateValue]),
                        bodyPrefix: Data(privateValue.utf8),
                        bodyState: .complete)),
                summary: "UpstreamWebSocketFailure.upgradeRejected"),
            .init(
                error: UpstreamWebSocketSendFailure(
                    submission: .mayHaveBeenSubmitted,
                    cause: .init(kind: .writeFailed)),
                summary: "UpstreamWebSocketFailure.writeFailed (mayHaveBeenSubmitted)"),
            .init(error: NativeDiagnosticPrivateError(), summary: "NativeDiagnosticPrivateError"),
        ]
        if #available(macOS 26, *) {
            cases.append(.init(error: NWError.wifiAware(7), summary: "NWError(code: 7)"))
        }
        return cases
    }
}

private struct NativeDiagnosticPrivateError: Error, CustomStringConvertible, LocalizedError {
    var description: String { NativeDiagnosticCase.privateValue }
    var errorDescription: String? { NativeDiagnosticCase.privateValue }
}
