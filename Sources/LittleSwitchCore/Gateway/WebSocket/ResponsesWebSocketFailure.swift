import Foundation
import LittleSwitchWire

package struct ResponsesWebSocketFailure: Error, Sendable {
    package let status: Int
    package let code: String
    package let message: String
    package let streamID: String?
    package let parameter: String?

    package init(status: Int, code: String, message: String, streamID: String? = nil, parameter: String? = nil) {
        self.status = status
        self.code = code
        self.message = message
        self.streamID = streamID
        self.parameter = parameter
    }

    package func encoded() throws -> Data {
        let type: ResponsesWebSocketContract.ErrorType =
            status >= 500 ? .serverError : (status == 429 ? .rateLimitError : .invalidRequestError)
        var fields: JSONObject = [
            OpenAIResponsesErrorEvent.Key.type.rawValue: .string(OpenAIResponsesErrorEventType.error.rawValue),
            OpenAIResponsesResponse.Key.status.rawValue: .integer(status),
            OpenAIResponsesResponse.Key.error.rawValue: [
                OpenAIResponsesErrorEvent.Key.type.rawValue: .string(type.rawValue),
                OpenAIResponsesErrorEvent.Key.code.rawValue: .string(code),
                OpenAIResponsesErrorEvent.Key.message.rawValue: .string(message),
                OpenAIResponsesErrorEvent.Key.param.rawValue: parameter.map(JSONValue.string) ?? .null,
            ],
        ]
        fields[ResponsesWebSocketContract.RequestField.streamID.rawValue] = streamID.map(JSONValue.string)
        return try JSONValue.object(fields).serializedData()
    }
}
