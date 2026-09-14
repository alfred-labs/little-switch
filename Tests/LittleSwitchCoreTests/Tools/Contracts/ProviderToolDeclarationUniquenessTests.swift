import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Provider tool declaration uniqueness")
struct ProviderToolDeclarationUniquenessTests {
    @Test("Repeated namespace/name declarations cannot create competing aliases", arguments: ["function", "custom"])
    func duplicateNamespaceIdentity(secondKind: String) throws {
        let tools: [[String: Any]] = [
            [
                "type": "namespace", "name": "workspace",
                "tools": [
                    ["type": "function", "name": "run", "parameters": ["type": "object"]],
                    ["type": secondKind, "name": "run", "parameters": ["type": "object"]],
                ],
            ]
        ]
        let root: [String: Any] = ["model": "client", "input": "Run.", "tools": tools]
        #expect(throws: ProviderToolContract.Error.invalidRequest) {
            try ProviderToolRequestPolicy.responses(root)
        }
        #expect(throws: ProviderToolContract.Error.invalidRequest) {
            try ProviderToolContract(wire: .responses, requestBody: chatJSONData(root))
        }
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
            try OpenAIResponsesChatCompletions.prepare(body: chatJSONData(root), targetModel: "upstream")
        }
    }
}
