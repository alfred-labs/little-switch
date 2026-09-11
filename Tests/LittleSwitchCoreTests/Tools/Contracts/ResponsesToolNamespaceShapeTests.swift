import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Namespace malformed shape reservations")
struct ResponsesToolNamespaceShapeTests {
    @Test("Missing types do not reserve identities or create namespace bindings")
    func missingTypes() {
        let flattened = ResponsesToolNamespaces.flatten(
            tools: [["name": "plain"], ["type": "namespace", "name": "workspace", "tools": [["name": "read"]]]],
            history: [["name": "old", "namespace": "workspace"]])
        #expect(flattened.tools as NSArray == [["name": "plain"]] as NSArray)
        #expect(flattened.bindings.isEmpty)
        #expect(flattened.declaredBindings.isEmpty)
    }
}
