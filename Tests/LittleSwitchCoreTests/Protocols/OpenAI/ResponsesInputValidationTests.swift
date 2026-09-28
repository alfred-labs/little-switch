import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Provider provenance validates complete input arrays")
struct ResponsesInputValidationTests {
    @Test("A malformed neighbor cannot bypass foreign reasoning filtering", arguments: [false, true])
    func mixedInput(native: Bool) throws {
        let providerID = UUID()
        let source = providerID
        let destination: UUID? = native ? nil : UUID()
        let wrapped = try ResponsesProviderState.tagged(
            ["type": "reasoning", "id": "rs_a", "encrypted_content": "synthetic-private"], providerID: source)
        let body = try responsesStreamData(["input": [wrapped, NSNull()]])
        #expect(throws: ResponsesProviderState.Error.invalidState) {
            try ResponsesProviderState.normalize(body: body, providerID: destination)
        }
        #expect(throws: ResponsesProviderState.Error.invalidState) {
            try ResponsesProviderState.expandedPortableBody(body)
        }
        #expect(throws: ResponsesProviderState.Error.invalidState) {
            try ResponsesProviderState.degradedBody(body)
        }
    }

    @Test("Unsupported input shapes fail before any stateful projection")
    func unsupportedShapes() throws {
        let invalid: [Any] = [17, true, ["type": "reasoning"], ["raw-text"]]
        for input in invalid {
            let body = try responsesStreamData(["input": input])
            #expect(throws: ResponsesProviderState.Error.invalidState) {
                try ResponsesProviderState.normalize(body: body, providerID: nil)
            }
            #expect(throws: ResponsesProviderState.Error.invalidState) {
                try ResponsesProviderState.expandedPortableBody(body)
            }
        }
    }

    @Test("Plain text and absent input preserve their exact bytes")
    func textAndAbsence() throws {
        for raw in [#"{ "input": "raw user text", "metadata": {} }"#, #"{"model":"m"}"#, #"{"input":null}"#] {
            let body = Data(raw.utf8)
            #expect(try ResponsesProviderState.normalize(body: body, providerID: nil) == body)
            #expect(try ResponsesProviderState.expandedPortableBody(body) == body)
            #expect(try ResponsesProviderState.degradedBody(body) == body)
        }
    }
}
