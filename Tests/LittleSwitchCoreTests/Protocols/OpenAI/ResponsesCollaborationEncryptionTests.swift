import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Codex collaboration argument encryption")
struct ResponsesCollaborationEncryptionTests {
    @Test(
        "Plaintext collaboration calls opt out of Codex's encrypted mail",
        arguments: ["spawn_agent", "send_message", "followup_task"])
    func plaintextMail(name: String) throws {
        let original = call(name: name)
        var expected = original
        expected["encrypted_function_args"] = [String]()
        let projected = try OpenAIResponsesPublicSanitizer.item(original)
        #expect(NSDictionary(dictionary: projected) == NSDictionary(dictionary: expected))
    }

    @Test("Explicit encryption metadata survives projection", arguments: [[], ["message"]])
    func explicitEncryption(arguments: [String]) throws {
        var original = call(name: "send_message")
        original["encrypted_function_args"] = arguments
        let projected = try OpenAIResponsesPublicSanitizer.item(original)
        #expect(NSDictionary(dictionary: projected) == NSDictionary(dictionary: original))
    }

    @Test("Null encryption metadata means unspecified")
    func nullEncryption() throws {
        var original = call(name: "send_message")
        original["encrypted_function_args"] = NSNull()
        let projected = try OpenAIResponsesPublicSanitizer.item(original)
        #expect((projected["encrypted_function_args"] as? [String])?.isEmpty == true)
    }

    @Test("Malformed encryption metadata cannot change how Codex interprets mail")
    func malformedEncryption() {
        for malformed: Any in ["message", [1], true] {
            var original = call(name: "send_message")
            original["encrypted_function_args"] = malformed
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                _ = try OpenAIResponsesPublicSanitizer.item(original)
            }
        }
    }

    @Test("Only collaboration functions that deliver mail receive the marker")
    func unrelatedTools() throws {
        for original in [
            call(name: "wait_agent"),
            call(name: "send_message", namespace: "messaging"),
            call(name: "collaboration__send_message", namespace: nil),
            call(name: "send_message", custom: true),
        ] {
            let projected = try OpenAIResponsesPublicSanitizer.item(original)
            #expect(NSDictionary(dictionary: projected) == NSDictionary(dictionary: original))
        }
    }

    private func call(name: String, namespace: String? = "collaboration", custom: Bool = false) -> [String: Any] {
        var result: [String: Any] = [
            "id": "fc_mail", "type": custom ? "custom_tool_call" : "function_call", "call_id": "call_mail",
            "name": name, custom ? "input" : "arguments": #"{"target":"/root","message":"Synthetic status update."}"#,
            "status": "completed",
        ]
        if let namespace { result["namespace"] = namespace }
        return result
    }
}
