import Foundation
import NIOHTTP1

public struct UpstreamWebSocketHTTPResponse: Sendable {
    public enum BodyState: Sendable, Equatable {
        case notApplicable
        case complete
        case limitReached
        case deadlineExpired
        case connectionClosed
        case invalidHTTP
    }

    public let head: HTTPResponseHead
    public let bodyPrefix: Data
    public let bodyState: BodyState

    public init(head: HTTPResponseHead, bodyPrefix: Data, bodyState: BodyState) {
        self.head = head
        self.bodyPrefix = bodyPrefix
        self.bodyState = bodyState
    }
}

public struct UpstreamWebSocketFailure: Error, Sendable, CustomStringConvertible {
    public enum Kind: Sendable, Equatable {
        case invalidConfiguration
        case invalidRequest
        case transportShutDown
        case shutdownFromConnection
        case inboundAlreadyConsumed
        case connectionFailed
        case tlsFailed
        case handshakeTimedOut
        case upgradeRejected
        case invalidUpgrade
        case protocolViolation
        case connectionLost
        case messageTooLarge
        case outboundQueueFull
        case connectionClosing
        case connectionEnded
        case writeFailed
        case closeTimedOut
        case cancelled
    }

    public let kind: Kind
    public let response: UpstreamWebSocketHTTPResponse?
    /// Validated numeric metadata only; never retain the peer's private reason.
    public let peerCloseCode: UInt16?

    public init(kind: Kind, response: UpstreamWebSocketHTTPResponse? = nil, peerCloseCode: UInt16? = nil) {
        self.kind = kind
        self.response = response
        self.peerCloseCode = peerCloseCode
    }

    public var description: String { "WebSocket failure: \(kind)" }
}

package struct UpstreamWebSocketSendFailure: Error, Sendable, CustomStringConvertible {
    package enum Submission: Sendable, Equatable {
        case notSubmitted
        case mayHaveBeenSubmitted
    }

    package let submission: Submission
    package let cause: UpstreamWebSocketFailure

    package init(submission: Submission, cause: UpstreamWebSocketFailure) {
        self.submission = submission
        self.cause = cause
    }

    package var description: String { "\(cause) (\(submission))" }
}
