import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Responses tool choice validation")
struct ResponsesToolChoiceValidationTests {
    @Test("Chat rejects unsupported scalar choices")
    func invalidChatRepresentations() throws {
        let values: [Any] = [42, NSNull(), "unsupported"]
        for value in values {
            #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
                _ = try ResponsesToolChoice.chat(value, bindings: [:])
            }
        }
    }

    @Test("Both wires reject malformed allowed selection envelopes")
    func malformedSelections() throws {
        let selections: [[String: Any]] = [
            [:], ["mode": "unknown", "tools": []],
            ["mode": "auto", "tools": "invalid"], ["mode": 42, "tools": []],
        ]
        for selection in selections {
            var choice = selection
            choice["type"] = "allowed_tools"
            #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
                _ = try ResponsesToolChoice.normalized(choice, bindings: [:])
            }
            #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
                _ = try ResponsesToolChoice.chat(choice, bindings: [:])
            }
        }
    }

    @Test("Chat rejects missing identities and unsupported selection kinds")
    func invalidChatReferences() throws {
        let references: [[String: Any]] = [
            [:], ["type": "function"], ["type": "function", "name": ""],
            ["type": "custom", "name": 42], ["type": "web_search"],
        ]
        for reference in references {
            #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
                _ = try ResponsesToolChoice.chat(reference, bindings: [:])
            }
        }
    }

    @Test("Namespace references cannot invent a binding or omit its name")
    func invalidNamespaces() throws {
        let references: [[String: Any]] = [
            ["type": "function", "name": "run", "namespace": 42],
            ["type": "function", "name": "run", "namespace": ""],
            ["type": "function", "name": "run", "namespace": "missing"],
            ["type": "function", "namespace": "workspace"],
        ]
        let bindings: [String: ResponsesToolNamespaces.Binding] = [
            "workspace__run": .init(namespace: "workspace", name: "run")
        ]
        for reference in references {
            #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
                _ = try ResponsesToolChoice.normalized(reference, bindings: bindings)
            }
            #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
                _ = try ResponsesToolChoice.chat(reference, bindings: bindings)
            }
        }
    }
}
