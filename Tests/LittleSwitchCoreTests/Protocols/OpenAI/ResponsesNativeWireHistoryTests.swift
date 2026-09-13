import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Responses native wire history")
struct ResponsesNativeWireHistoryTests {
    @Test(
        "Absent or null history grants no tool identity and preserves the original request",
        arguments: [
            #"{ "model": "client", "vendor": {"type":"function","name":"hidden"} }"#,
            #"{"model":"client","input":null,"tools":null,"tool_choice":null}"#,
        ])
    func absentHistoryPreservesTheRequest(body: String) throws {
        let data = Data(body.utf8)
        let normalized = try OpenAIResponsesNativeNamespacing.normalize(data)
        #expect(normalized.body == data)
        #expect(normalized.toolNameCatalog == ProviderToolNameCatalog())
        #expect(normalized.toolBindings.isEmpty)
        #expect(normalized.declaredToolBindings.isEmpty)
        #expect(normalized.droppedMailCount == 0)
    }

    @Test("Namespace normalization preserves opaque request, schema and custom-output numbers")
    func normalizationPreservesOpaqueNumbers() throws {
        let data = Data(
            #"""
            {"model":"client","tools":[{"type":"namespace","name":"workspace","tools":[
              {"type":"custom","name":"patch","vendor_schema":{"tiny":1e-400}}
            ]}],"input":[
              {"type":"custom_tool_call","id":"ct_1","call_id":"call_1","name":"patch","namespace":"workspace",
               "input":"*** Begin Patch\nΔ","vendor":18446744073709551617},
              {"type":"custom_tool_call_output","call_id":"call_1","output":{"tiny":1e-400}}
            ],"vendor":{"huge":18446744073709551617,"tiny":1e-400}}
            """#
            .utf8)
        let normalized = try OpenAIResponsesNativeNamespacing.normalize(data)
        let original = try #require(JSONValue.parse(data).object)
        let actual = try #require(JSONValue.parse(normalized.body).object)
        #expect(actual["vendor"] == original["vendor"])
        #expect(actual["input"]?.array?[0].object?["vendor"] == original["input"]?.array?[0].object?["vendor"])
        #expect(actual["input"]?.array?[1] == original["input"]?.array?[1])
        #expect(
            actual["tools"]?.array?[0].object?["vendor_schema"]
                == original["tools"]?.array?[0].object?["tools"]?.array?[0].object?["vendor_schema"])
    }
}
