@testable import LittleSwitchCore

func startedCoveragePublicSession() throws -> AnthropicPublicStreamSession {
    var session = AnthropicPublicStreamSession(originalModel: "claude")
    _ = try session.start(from: messageStartEvent(id: "msg_coverage", inputTokens: 0))
    return session
}
