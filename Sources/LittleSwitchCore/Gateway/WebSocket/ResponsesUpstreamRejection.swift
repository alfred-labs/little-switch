import Foundation
import LittleSwitchWire
import NIOHTTP1

/// Before response.created, the first error is a rejected model request, not
/// a successful SSE exchange. Preserve its HTTP error object for the existing
/// capability and image-rejection policies. Invalid/missing statuses use 400.
struct ResponsesUpstreamRejection: Sendable {
    let status: HTTPResponseStatus
    let body: Data

    init(_ event: JSONObject) throws {
        typealias ErrorKey = OpenAIResponsesErrorEvent.Key
        typealias ResponseKey = OpenAIResponsesResponse.Key
        let proposed = event[ResponseKey.status.rawValue]?.integer ?? 400
        let code = (400..<600).contains(proposed) ? proposed : 400
        status = .init(statusCode: code)
        let error: JSONValue
        if let nested = event[ResponseKey.error.rawValue]?.object {
            error = .object(nested)
        } else {
            let type: ResponsesWebSocketContract.ErrorType =
                code >= 500 ? .serverError : (code == 429 ? .rateLimitError : .invalidRequestError)
            error = .object([
                ErrorKey.type.rawValue: .string(type.rawValue),
                ErrorKey.code.rawValue: event[ErrorKey.code.rawValue]
                    ?? .string(ResponsesWebSocketContract.ErrorCode.upstreamError.rawValue),
                ErrorKey.message.rawValue: event[ErrorKey.message.rawValue] ?? .string("Provider request failed"),
                ErrorKey.param.rawValue: event[ErrorKey.param.rawValue] ?? .null,
            ])
        }
        body = try JSONValue.object([ResponseKey.error.rawValue: error]).serializedData()
    }
}
