import Foundation
import LittleSwitchWire

/// Public events have already passed the gateway's provider and tool policies.
/// Preserve their open JSON contract while isolating each response's retained output.
package struct ResponsesWebSocketEvents {
    private typealias EventKey = OpenAIResponsesCreatedEvent.Key
    private typealias ResponseKey = OpenAIResponsesResponse.Key
    private typealias ItemKey = OpenAIResponsesOutputItemDoneEvent.Key
    private typealias ErrorKey = OpenAIResponsesErrorEvent.Key
    package enum Error: Swift.Error, Equatable {
        case invalidEvent
        case mismatchedResponse
        case missingTerminal
        case eventAfterTerminal
        case tooLarge
    }

    private let streamID: String?
    private let maximumBytes: Int
    private let maximumOutputItems: Int
    private var responseID: String?
    private var items: [Int: JSONValue] = [:]
    private var itemSizes: [Int: Int] = [:]
    private var retainedBytes = 0
    private var terminal: ResponsesWebSocketEventResult?

    package init(streamID: String?, maximumBytes: Int, maximumOutputItems: Int = 4_096) {
        self.streamID = streamID
        self.maximumBytes = maximumBytes
        self.maximumOutputItems = maximumOutputItems
    }

    /// A terminal is returned by finish(), after the HTTP body and permit finish.
    /// The coordinator installs its cache entry before publishing that terminal.
    package mutating func accept(_ data: Data) throws -> Data? {
        guard terminal == nil else { throw Error.eventAfterTerminal }
        guard data.count <= maximumBytes else { throw Error.tooLarge }
        guard let parsed = try? JSONValue.parse(data), var event = parsed.object,
            let type = event[EventKey.type.rawValue]?.string, !type.isEmpty
        else { throw Error.invalidEvent }
        event[ResponsesWebSocketContract.RequestField.streamID.rawValue] = streamID.map(JSONValue.string)
        if let identifier = event[EventKey.response.rawValue]?.object?[ResponseKey.id.rawValue]?.string {
            if let responseID, identifier != responseID { throw Error.mismatchedResponse }
            responseID = identifier
        }
        let referencedID = event[ResponsesWebSocketContract.EventField.responseID.rawValue]?.string
        if let referencedID, let responseID, referencedID != responseID { throw Error.mismatchedResponse }
        switch type {
        case OpenAIResponsesOutputItemDoneEventType.responseOutputItemDone.rawValue:
            try recordCompletedItem(event)
        case OpenAIResponsesCompletedEventType.responseCompleted.rawValue,
            OpenAIResponsesIncompleteEventType.responseIncomplete.rawValue:
            try recordTerminal(event)
            return nil
        case OpenAIResponsesFailedEventType.responseFailed.rawValue:
            terminal = ResponsesWebSocketEventResult(
                terminal: try encode(event), responseID: nil, output: nil)
            discardItems()
            return nil
        case OpenAIResponsesErrorEventType.error.rawValue:
            terminal = ResponsesWebSocketEventResult(
                terminal: try encode(Self.errorEnvelope(event)), responseID: nil, output: nil)
            discardItems()
            return nil
        default:
            break
        }
        return try encode(event)
    }

    package func finish() throws -> ResponsesWebSocketEventResult {
        guard let terminal else { throw Error.missingTerminal }
        return terminal
    }

    private mutating func recordCompletedItem(_ event: JSONObject) throws {
        guard let index = event[ItemKey.outputIndex.rawValue]?.integer, index >= 0,
            let item = event[ItemKey.item.rawValue], item.object != nil
        else { throw Error.invalidEvent }
        guard items[index] != nil || items.count < maximumOutputItems else { throw Error.tooLarge }
        let size = try item.serializedData().count
        let newSize = retainedBytes - (itemSizes[index] ?? 0) + size
        guard newSize <= maximumBytes else { throw Error.tooLarge }
        items[index] = item
        itemSizes[index] = size
        retainedBytes = newSize
    }

    private mutating func recordTerminal(_ event: JSONObject) throws {
        guard var response = event[EventKey.response.rawValue]?.object,
            let identifier = response[ResponseKey.id.rawValue]?.string,
            !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            var output = response[ResponseKey.output.rawValue]?.array,
            output.allSatisfy({ $0.object != nil })
        else { throw Error.invalidEvent }
        if output.isEmpty { output = items.sorted { $0.key < $1.key }.map(\.value) }
        response[ResponseKey.output.rawValue] = .array(output)
        var completed = event
        completed[EventKey.response.rawValue] = .object(response)
        terminal = ResponsesWebSocketEventResult(
            terminal: try encode(completed),
            responseID: identifier,
            output: try JSONValue.array(output).serializedData())
        discardItems()
    }

    private mutating func discardItems() {
        items.removeAll()
        itemSizes.removeAll()
        retainedBytes = 0
    }

    private func encode(_ event: JSONObject) throws -> Data {
        let data = try JSONValue.object(event).serializedData()
        guard data.count <= maximumBytes else { throw Error.tooLarge }
        return data
    }

    package static func errorEnvelope(_ event: JSONObject, status: Int = 502) -> JSONObject {
        var result = event
        if result[ResponseKey.error.rawValue]?.object == nil {
            result[ResponseKey.error.rawValue] = .object([
                ErrorKey.type.rawValue: .string(ResponsesWebSocketContract.ErrorType.serverError.rawValue),
                ErrorKey.code.rawValue: result.removeValue(forKey: ErrorKey.code.rawValue) ?? .string("upstream_error"),
                ErrorKey.message.rawValue: result.removeValue(forKey: ErrorKey.message.rawValue)
                    ?? .string("Provider response failed"),
                ErrorKey.param.rawValue: result.removeValue(forKey: ErrorKey.param.rawValue) ?? .null,
            ])
        }
        result[EventKey.type.rawValue] = OpenAIResponsesErrorEventType.error.wireJSON()
        if result[ResponseKey.status.rawValue]?.integer == nil {
            result[ResponseKey.status.rawValue] = .integer(status)
        }
        return result
    }
}

package struct ResponsesWebSocketEventResult: Sendable {
    package let terminal: Data
    package let responseID: String?
    package let output: Data?
}
