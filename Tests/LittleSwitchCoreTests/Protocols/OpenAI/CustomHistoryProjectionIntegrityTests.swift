import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Retired custom history integrity")
struct CustomHistoryProjectionIntegrityTests {
    @Test("Orphan results cannot reuse a custom result ID with another kind", arguments: [false, true])
    func orphanResultKinds(reversed: Bool) throws {
        var output = try #require(
            JSONValue.parse(
                #"[{"type":"custom_tool_call_output","call_id":"orphan","output":"a"},{"type":"function_call_output","call_id":"orphan","output":"b"}]"#
            ).array)
        if reversed { output.reverse() }
        let body = try JSONValue.object(["model": .string("m"), "input": .array(output)]).serializedData()
        #expect(throws: ResponsesCustomToolHistory.Error.invalidHistory) {
            _ = try OpenAIResponsesNativeNamespacing.normalize(body)
        }
    }

    @Test("Archived history keeps its original namespace, kind, IDs and opaque fields")
    func exactHistory() throws {
        let body = Data(
            #"""
            {"model":"route","input":[
              {"type":"custom_tool_call","namespace":"a__b","name":"c","call_id":"old",
               "input":"\u0000\r\né e\u0301 🙂","id":"ct","status":"completed","opaque":1e300},
              {"type":"custom_tool_call_output","call_id":"old","id":"result",
               "output":[{"type":"input_text","text":"literal {\"input\":\"x\"}"}],"opaque":-0.000}
            ],"tools":[{"type":"namespace","name":"a","tools":[{"type":"custom","name":"b__c"}]}]}
            """#.utf8)
        let source = try #require(JSONValue.parse(body).object?["input"]?.array)
        let normalized = try OpenAIResponsesNativeNamespacing.normalize(body)
        let items = try #require(JSONValue.parse(normalized.body).object?["input"]?.array)
        let restored = try items.map(historyArchiveItem)
        #expect(restored == source)
        // JSONValue's String equality treats canonically equivalent Unicode as
        // equal. The archived freeform program must preserve the actual bytes.
        let originalInput = try #require(source[0].object?["input"]?.string)
        let restoredInput = try #require(restored[0].object?["input"]?.string)
        #expect(Data(restoredInput.utf8) == Data(originalInput.utf8))
        #expect(try historyArchiveItem(items[0]).object?["opaque"]?.numberLiteral?.rawValue == "1e300")
        #expect(try historyArchiveItem(items[1]).object?["opaque"]?.numberLiteral?.rawValue == "-0.000")
        #expect(try OpenAIResponsesNativeNamespacing.normalize(normalized.body).body == normalized.body)
    }

    @Test(
        "A result ID has one unambiguous call kind and one output",
        arguments: [
            #"{"type":"custom_tool_call","call_id":"old","name":"active","input":"second"}"#,
            #"{"type":"function_call","call_id":"old","name":"shell","arguments":"{}"}"#,
            #"{"type":"custom_tool_call_output","call_id":"old","output":"second result"}"#,
            #"{"type":"function_call_output","call_id":"old","output":"wrong result kind"}"#,
        ])
    func rejectsAmbiguousPairs(extra: String) throws {
        let body = Data(
            ("""
            {"model":"route","tools":[{"type":"custom","name":"active"}],"input":[
              {"type":"custom_tool_call","call_id":"old","name":"retired","input":"first"},
              {"type":"custom_tool_call_output","call_id":"old","output":"first result"},
              \(extra)
            ]}
            """).utf8)
        #expect(throws: ResponsesCustomToolHistory.Error.invalidHistory) {
            _ = try OpenAIResponsesNativeNamespacing.normalize(body)
        }
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
            _ = try OpenAIResponsesChatCompletions.prepare(body: body, targetModel: "provider")
        }
    }

    @Test("An image result remains visible without putting its base64 in text")
    func imageArchiveRoundTrip() throws {
        let body = Data(
            #"""
            {"model":"route","input":[
              {"type":"custom_tool_call","call_id":"old","name":"exec","input":"image(result)"},
              {"type":"custom_tool_call_output","call_id":"old","output":[
                {"type":"input_text","text":"before"},
                {"type":"input_image","image_url":"data:image/png;base64,AA==","detail":"high","opaque":1e300},
                {"type":"input_text","text":"after"},
                {"type":"input_image","image_url":"https://example.test/image.png","detail":"low"}
              ]}
            ]}
            """#.utf8)
        let original = try #require(JSONValue.parse(body).object?["input"]?.array)
        let normalized = try OpenAIResponsesNativeNamespacing.normalize(body)
        let items = try #require(JSONValue.parse(normalized.body).object?["input"]?.array)
        #expect(try items.map(historyArchiveItem) == original)
        let parts = try #require(items[1].object?["content"]?.array)
        #expect(parts.count == 3)
        #expect(items[1].object?["role"] == .string("user"))
        #expect(parts[0].object?["text"]?.string?.contains("base64") == false)
        #expect(parts[1] == original[1].object?["output"]?.array?[1])
        #expect(parts[2] == original[1].object?["output"]?.array?[3])
        #expect(try JSONValue.parse(normalized.body).object?["max_output_tokens"] != nil)
        let chat = try OpenAIResponsesChatCompletions.prepare(body: body, targetModel: "provider")
        let messages = try #require(JSONValue.parse(chat.upstreamBody).object?["messages"]?.array)
        let content = try #require(messages[1].object?["content"]?.array)
        #expect(content.count == 3)
        #expect(content[0].object?["text"]?.string?.contains("base64") == false)
        #expect(content[1].object?["image_url"]?.object?["url"] == .string("data:image/png;base64,AA=="))
        #expect(content[2].object?["image_url"]?.object?["detail"] == .string("low"))
        #expect(try historyArchiveItem(messages[1]) == original[1])
        #expect(
            try historyArchiveItem(messages[1]).object?["output"]?.array?[1].object?["opaque"]?.numberLiteral?.rawValue
                == "1e300")
    }

    @Test("Retired results cannot interrupt the results of parallel current calls", arguments: [false, true])
    func mixedParallelResults(unicodeIDs: Bool) throws {
        let body = Data(
            #"""
            {"model":"route","tools":[{"type":"function","name":"shell"}],"input":[
              {"type":"function_call","call_id":"a","name":"shell","arguments":"{}"},
              {"type":"custom_tool_call","call_id":"old","name":"exec","input":"old"},
              {"type":"function_call","call_id":"b","name":"shell","arguments":"{}"},
              {"type":"function_call_output","call_id":"a","output":"a"},
              {"type":"custom_tool_call_output","call_id":"old","output":"old"},
              {"type":"function_call_output","call_id":"b","output":"b"}
            ]}
            """#.utf8)
        let firstID = unicodeIDs ? "é" : "a"
        let secondID = unicodeIDs ? "e\u{301}" : "b"
        let text = try #require(String(bytes: body, encoding: .utf8))
            .replacingOccurrences(of: "\"call_id\":\"a\"", with: "\"call_id\":\"\(firstID)\"")
            .replacingOccurrences(of: "\"call_id\":\"b\"", with: "\"call_id\":\"\(secondID)\"")
        let request = try OpenAIResponsesChatCompletions.prepare(body: Data(text.utf8), targetModel: "provider")
        let messages = try #require(JSONValue.parse(request.upstreamBody).object?["messages"]?.array)
        #expect(messages.count == 4)
        #expect(
            messages.map { $0.object?["role"] } == [
                .string("assistant"), .string("tool"), .string("tool"), .string("assistant"),
            ])
        #expect(
            messages[0].object?["tool_calls"]?.array?.map { $0.object?["id"] } == [.string(firstID), .string(secondID)])
        #expect(messages[1].object?["tool_call_id"] == .string(firstID))
        #expect(messages[2].object?["tool_call_id"] == .string(secondID))
        #expect(try historyArchiveItem(messages[0]).object?["input"] == .string("old"))
        #expect(try historyArchiveItem(messages[3]).object?["call_id"] == .string("old"))
    }

    @Test("A new call cannot interrupt a parallel turn with deferred historical context")
    func rejectsInterruptedParallelTurn() throws {
        let body = Data(
            #"""
            {"model":"route","tools":[{"type":"function","name":"shell"}],"input":[
              {"type":"function_call","call_id":"a","name":"shell","arguments":"{}"},
              {"type":"function_call","call_id":"b","name":"shell","arguments":"{}"},
              {"type":"function_call_output","call_id":"a","output":"a"},
              {"type":"custom_tool_call_output","call_id":"old","output":"historical result"},
              {"type":"function_call","call_id":"c","name":"shell","arguments":"{}"},
              {"type":"function_call_output","call_id":"b","output":"b"}
            ]}
            """#.utf8)
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
            _ = try OpenAIResponsesChatCompletions.prepare(body: body, targetModel: "provider")
        }
    }
}

/// Test-side inverse verifies the whole original item, including unknown fields.
func historyArchiveItem(_ message: JSONValue) throws -> JSONValue {
    let parts = message.object?["content"]?.array
    let text = try #require(message.object?["content"]?.string ?? parts?.first?.object?["text"]?.string)
    let newline = try #require(text.firstIndex(of: "\n"))
    let archive = try JSONValue.parse(String(text[text.index(after: newline)...]))
    guard let attachments = archive.object?["attachments"]?.array, let parts, parts.count > 1 else { return archive }
    var item = try #require(archive.object?["item"]?.object)
    var output = try #require(item["output"]?.array)
    for attachment in attachments {
        let outputIndex = Int(try #require(attachment.object?["output_index"]?.number))
        let contentIndex = Int(try #require(attachment.object?["content_index"]?.number))
        var skeleton = try #require(output[outputIndex].object)
        let attachmentURL = try #require(parts[contentIndex].object?["image_url"])
        skeleton["image_url"] = attachmentURL.object?["url"] ?? attachmentURL
        output[outputIndex] = .object(skeleton)
    }
    item["output"] = .array(output)
    return .object(item)
}
