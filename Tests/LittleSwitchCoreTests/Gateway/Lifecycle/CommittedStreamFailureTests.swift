import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Committed stream failure")
struct CommittedStreamFailureTests {
    @Test("A failure without a reason keeps the generic traffic message")
    func genericMessage() {
        #expect(GatewayCommittedStreamFailure().trafficMessage == "Response stream reported failure")
    }

    @Test("A failure carries its reason into the traffic message")
    func reasonIsSurfaced() {
        let failure = GatewayCommittedStreamFailure(reason: "invalidResponse")

        #expect(failure.reason == "invalidResponse")
        #expect(
            failure.trafficMessage == "Response stream reported failure: invalidResponse"
        )
    }
}
