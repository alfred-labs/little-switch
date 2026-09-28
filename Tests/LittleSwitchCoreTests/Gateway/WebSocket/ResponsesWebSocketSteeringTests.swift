import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Responses WebSocket steering")
struct ResponsesWebSocketSteeringTests {
    @Test("A valid steering envelope reaches the connection coordinator")
    func steeringEnvelope() throws {
        let envelope = try ResponsesWebSocketRequest.Envelope(
            Data(#"{"type":"response.steer","previous_response_id":"resp_active","input":"Keep it small"}"#.utf8),
            maximumBytes: 1_024)
        #expect(envelope.previousResponseID == "resp_active")
    }

    @Test(
        "Steering rejects model settings, lane fields and non-user or malformed content",
        arguments: [
            #"{"type":"response.steer","previous_response_id":"r1","input":"text","stream_id":"lane"}"#,
            #"{"type":"response.steer","previous_response_id":"r1","input":"text","model":"other"}"#,
            #"{"type":"response.steer","previous_response_id":"r1","input":[]}"#,
            #"{"type":"response.steer","previous_response_id":"r1","input":[{"role":"assistant","content":"text"}]}"#,
            #"{"type":"response.steer","previous_response_id":"r1","input":[{"type":"function_call_output","call_id":"c1","output":"text"}]}"#,
            #"{"type":"response.steer","previous_response_id":"r1","input":[{"role":"user","content":[{"type":"input_text","text":4}]}]}"#,
            #"{"type":"response.steer","previous_response_id":"r1","input":[{"role":"user","content":[{"type":"input_image"}]}]}"#,
            #"{"type":"response.steer","previous_response_id":"r1","input":[{"role":"user","content":[{"type":"input_file"}]}]}"#,
        ])
    func invalidSteering(_ json: String) throws {
        let envelope = try ResponsesWebSocketRequest.Envelope(Data(json.utf8), maximumBytes: 4_096)
        #expect(throws: ResponsesWebSocketFailure.self) { try ResponsesWebSocketSteering(envelope) }
    }
}
