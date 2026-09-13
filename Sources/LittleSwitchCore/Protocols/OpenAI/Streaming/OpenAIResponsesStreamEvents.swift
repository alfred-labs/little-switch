import Foundation
import LittleSwitchWire

struct ResponsesToolInputReference {
    let index: Int
    let itemID: String
    let callID: String
    let name: String
}

package enum ResponsesProviderStreamEvent: Equatable, Sendable {
    case responseStarted(responseJSON: Data)
    case outputItemAdded(outputIndex: Int, itemJSON: Data)
    case outputItemDone(outputIndex: Int, itemJSON: Data)
    case contentPartAdded(
        outputIndex: Int,
        contentIndex: Int,
        itemID: String,
        partJSON: Data
    )
    case outputTextDelta(
        outputIndex: Int,
        contentIndex: Int,
        itemID: String,
        delta: String
    )
    case outputTextDone(
        outputIndex: Int,
        contentIndex: Int,
        itemID: String,
        text: String
    )
    // The normalized boundary deliberately keeps the exact five-field contract.
    // swiftlint:disable:next enum_case_associated_values_count
    case functionArgumentsDelta(
        outputIndex: Int,
        itemID: String,
        callID: String,
        name: String,
        delta: String
    )
    // The normalized boundary deliberately keeps the exact five-field contract.
    // swiftlint:disable:next enum_case_associated_values_count
    case functionArgumentsDone(
        outputIndex: Int,
        itemID: String,
        callID: String,
        name: String,
        arguments: String
    )
    // The custom input stream carries the same exact identity boundary.
    // swiftlint:disable:next enum_case_associated_values_count
    case customInputDelta(outputIndex: Int, itemID: String, callID: String, name: String, delta: String)
    // swiftlint:disable:next enum_case_associated_values_count
    case customInputDone(outputIndex: Int, itemID: String, callID: String, name: String, input: String)
    case passthrough(type: String, payloadJSON: Data)
    case terminal(status: ResponsesStreamTerminal, responseJSON: Data)
}

package enum ResponsesStreamTerminal: String, Equatable, Sendable {
    case completed
    case incomplete
    case failed
}

package func validResponsesFailedResponse(
    _ response: [String: Any],
    expectedID: String? = nil
) -> Bool {
    guard let id = nonemptyResponsesString(response["id"]),
        expectedID == nil || id == expectedID,
        response["object"] as? String == "response",
        response["status"] as? String == ResponsesStreamTerminal.failed.rawValue
    else {
        return false
    }
    // Providers may fail a response without filling the error object at all
    // (some providers stream `"error": null`). That is a protocol slip, not an
    // unparseable frame: the terminal itself is well formed, so accept it and
    // let the caller name the missing cause.
    if let error = response["error"], !(error is NSNull) {
        guard let error = error as? [String: Any],
            nonemptyResponsesString(error["code"]) != nil,
            error["message"] is String
        else {
            return false
        }
    }
    if let output = response["output"], !(output is [Any]) {
        return false
    }
    if let usage = response["usage"], !(usage is NSNull), !(usage is [String: Any]) {
        return false
    }
    return true
}

package func nonemptyResponsesString(_ value: Any?) -> String? {
    guard let value = value as? String, !value.isEmpty else {
        return nil
    }
    return value
}

package func nonnegativeResponsesIndex(_ value: Any?) -> Int? {
    guard let value, let json = try? WireJSONCompatibility.value(value),
        let number = json.numberLiteral
    else { return nil }
    return try? responsesWireIndex(number)
}

package func responsesStreamObject(_ data: Data) throws -> [String: Any] {
    do {
        return try WireJSONCompatibility.fields(data)
    } catch {
        throw OpenAIResponsesWebSearch.Error.invalidResponse
    }
}

package func responsesStreamData(_ value: Any) throws -> Data {
    do {
        return try WireJSONCompatibility.data(value)
    } catch {
        throw OpenAIResponsesWebSearch.Error.invalidResponse
    }
}
