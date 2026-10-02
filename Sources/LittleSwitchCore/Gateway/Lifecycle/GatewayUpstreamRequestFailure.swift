import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import NIOCore
import NIOHTTP2
import NIOSSL
// swift-format sorts case-sensitively; SwiftLint sorts case-insensitively.
// swiftlint:disable:next sorted_imports
import Network

/// Only a safe diagnostic crosses the request lifecycle. Never retain or print
/// arbitrary error descriptions, URL user info, headers, bodies or TLS stacks.
struct GatewayUpstreamRequestFailure: Error, Sendable {
    private let diagnostic: String

    init(_ cause: any Error) {
        diagnostic = Self.summary(cause)
    }

    func message(eventID: UUID) -> String {
        "Provider request failed: \(diagnostic) (request \(eventID))"
    }

    static func summary(_ error: any Error) -> String {
        switch error {
        case let error as HTTPClientError:
            return identifier(error.description)
        case let error as URLError:
            return "URLError(code: \(error.code.rawValue))"
        case let error as NWError:
            return networkSummary(error)
        case let error as IOError:
            return "IOError(errno: \(error.errnoCode))"
        case let error as NIOHTTP2Errors.StreamClosed:
            return "NIOHTTP2Errors.StreamClosed(code: \(error.errorCode.networkCode))"
        case let error as NIOSSLError:
            let name = "NIOSSLError.\(identifier(String(describing: error)))"
            switch error {
            case .handshakeFailed(let cause), .shutdownFailed(let cause):
                return "\(name)(\(identifier(String(describing: cause))))"
            default:
                return name
            }
        case let error as NIOSSLExtraError:
            return identifier(error.description)
        case let error as ChannelError:
            return "ChannelError.\(channelCase(error))"
        case let error as UpstreamWebSocketFailure:
            let summary = "UpstreamWebSocketFailure.\(error.kind)"
            if let code = error.peerCloseCode { return "\(summary) (peerCloseCode: \(code))" }
            return summary
        case let error as UpstreamWebSocketSendFailure:
            return "\(summary(error.cause)) (\(error.submission))"
        default:
            // All Swift errors bridge to NSError. Inspect the actual type first
            // so an unknown Swift error keeps its type, never its description.
            if type(of: error) is NSError.Type {
                return "NSError(code: \((error as NSError).code))"
            }
            return String(describing: type(of: error))
        }
    }

    /// ChannelError's description is prose, not an enum identifier, and some
    /// cases embed socket/interface addresses. Match its cases explicitly.
    private static func channelCase(_ error: ChannelError) -> String {
        switch error {
        case .connectPending: "connectPending"
        case .connectTimeout: "connectTimeout"
        case .operationUnsupported: "operationUnsupported"
        case .ioOnClosedChannel: "ioOnClosedChannel"
        case .alreadyClosed: "alreadyClosed"
        case .outputClosed: "outputClosed"
        case .inputClosed: "inputClosed"
        case .eof: "eof"
        case .writeMessageTooLarge: "writeMessageTooLarge"
        case .writeHostUnreachable: "writeHostUnreachable"
        case .unknownLocalAddress: "unknownLocalAddress"
        case .badMulticastGroupAddressFamily: "badMulticastGroupAddressFamily"
        case .badInterfaceAddressFamily: "badInterfaceAddressFamily"
        case .illegalMulticastAddress: "illegalMulticastAddress"
        case .multicastNotSupported: "multicastNotSupported"
        case .inappropriateOperationForState: "inappropriateOperationForState"
        case .unremovableHandler: "unremovableHandler"
        }
    }

    private static func networkSummary(_ error: NWError) -> String {
        switch error {
        case .posix(let code): "NWError.posix(code: \(code.rawValue))"
        case .tls(let code): "NWError.tls(code: \(code))"
        case .dns(let code): "NWError.dns(code: \(code))"
        // Newer systems also expose Wi-Fi Aware errors. Keep their numeric
        // CustomNSError code without raising the app's macOS 14 requirement.
        default: "NWError(code: \(error.errorCode))"
        }
    }

    /// The pinned AHC/NIO errors above start with a static case identifier,
    /// followed by associated values in parentheses or a colon-delimited detail.
    /// Keep only that identifier; this is NOT a sanitizer for arbitrary errors.
    private static func identifier(_ description: String) -> String {
        String(
            description.prefix(96).prefix { character in
                character.isASCII && (character.isLetter || character.isNumber || character == "_" || character == ".")
            })
    }
}
