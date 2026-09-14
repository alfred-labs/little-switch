import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Traffic failure diagnostics")
struct TrafficFailureDiagnosticTests {
    @Test("Legacy failure records decode and extended records round-trip without losing names")
    func compatibility() throws {
        let old = Data(#"{"kind":"stream","message":"failed"}"#.utf8)
        #expect(try JSONDecoder().decode(TrafficFailure.self, from: old) == .init(kind: "stream", message: "failed"))
        let failure = TrafficFailure(
            kind: "stream", message: "failed", toolName: "run\n</arg_value>", toolNamespace: "tools")
        let encoded = try JSONEncoder().encode(failure)
        #expect(try JSONDecoder().decode(TrafficFailure.self, from: encoded) == failure)
        #expect(!encoded.contains(0x0A))
    }

    @Test("Tool metadata is bounded and absent from generic error descriptions")
    func boundedMetadata() {
        let name = String(repeating: "x", count: 600)
        let error = ProviderToolContract.Error.undeclaredTool(name: name, namespace: "private")
        #expect(String(describing: error) == "undeclaredTool")
        for (error, description) in [
            (ProviderToolContract.Error.invalidRequest, "invalidRequest"),
            (.invalidResponse, "invalidResponse"), (.providerOwnedTool, "providerOwnedTool"),
        ] {
            #expect(String(describing: error) == description)
        }
        let committed = GatewayCommittedStreamFailure(reason: "undeclaredTool", toolError: error)
        #expect(
            committed.trafficFailure
                == .init(
                    kind: "stream",
                    message: "Response stream reported failure: undeclaredTool",
                    toolName: String(repeating: "x", count: 512) + "…",
                    toolNamespace: "private"
                ))
        #expect(TrafficDiagnosticText.bounded("a\u{0301}\u{0301}", limit: 2).unicodeScalars.count == 3)
        #expect(TrafficDiagnosticText.bounded("x", limit: -1) == "…")
    }
}
