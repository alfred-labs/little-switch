import Foundation
import LittleSwitchWire

/// A retirement reports every unapplied intent, including already acknowledged
/// steering that the retired provider connection can no longer apply.
struct ResponsesUpstreamSteeringFailure: Sendable {
    let identifier: String?
    let previousResponseID: String
    let code: ResponsesWebSocketContract.ErrorCode
    let observer: (@Sendable (String) -> Void)?

    func encoded() throws -> Data {
        typealias EventKey = OpenAIResponsesErrorEvent.Key
        typealias SteeringField = ResponsesWebSocketContract.SteeringField
        var steer: JSONObject = [
            SteeringField.previousResponseID.rawValue: .string(previousResponseID)
        ]
        steer[SteeringField.id.rawValue] = identifier.map(JSONValue.string)
        let message =
            code == .steeringAcknowledgementTimeout
            ? "The provider did not acknowledge steering before the deadline. Explicitly resubmit this unapplied input."
            : "The upstream connection was retired before applying this steering. Explicitly resubmit this unapplied input."
        let event: JSONValue = [
            EventKey.type.rawValue: .string(ResponsesWebSocketContract.Event.steerFailed.rawValue),
            ResponsesWebSocketContract.ControlField.steer.rawValue: .object(steer),
            OpenAIResponsesResponse.Key.error.rawValue: [
                EventKey.code.rawValue: .string(code.rawValue),
                EventKey.message.rawValue: .string(message),
            ],
        ]
        return try event.serializedData()
    }
}
