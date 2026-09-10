import Foundation
import Testing

@testable import LittleSwitchCore

extension CodexAutoReviewTests {
    @Test(
        "The reviewer shares the provider queue and a changed reviewer invalidates queued reviews",
        arguments: [false, true])
    func sharedAdmission(changesReviewer: Bool) async throws {
        var snapshot = makeSnapshot()
        snapshot.codex.autoReviewModel = snapshot.codex.defaultModel
        snapshot.providers[0].maximumParallelRequests = 1
        let provider = try #require(snapshot.providers.first)
        let state = GatewayState(snapshot: snapshot)
        let capture = await state.routingCapture()
        let activeID = UUID()
        let reviewerID = UUID()

        try await state.admit(
            GatewayRequestAdmission(
                eventID: activeID,
                capture: capture,
                client: .codex,
                modelIdentifier: "example/xlarge",
                providerID: provider.id,
                targetModelID: "xlarge",
                retainedBodyBytes: 1))
        let reviewer = Task {
            try await state.admit(
                GatewayRequestAdmission(
                    eventID: reviewerID,
                    capture: capture,
                    client: .codex,
                    modelIdentifier: "codex-auto-review",
                    providerID: provider.id,
                    targetModelID: "xlarge",
                    retainedBodyBytes: 1))
        }
        defer { reviewer.cancel() }
        let queued: ProviderRequestPoolSnapshot = try await eventually(
            description: "the reviewer to enter the provider queue"
        ) {
            let current = await state.requestPoolSnapshot()
            return current.totalWaiting == 1 ? current : nil
        }
        #expect(queued.totalRunning == 1)
        #expect(await state.codexSessionRequestCount == 1)

        if changesReviewer {
            snapshot.codex.autoReviewModel = ModelMapping(providerID: provider.id, modelID: "small")
            let replacement = await state.replace(
                providers: snapshot.providers, mappings: snapshot.mappings, codex: snapshot.codex)
            #expect(replacement.resolveCodex(model: "codex-auto-review")?.model.id == "small")
            await #expect(throws: GatewayAdmissionError.invalidated) {
                try await reviewer.value
            }
            #expect(await state.codexSessionRequestCount == 1)
            await state.finish(eventID: activeID)
        } else {
            await state.finish(eventID: activeID)
            try await reviewer.value
            #expect(await state.codexSessionRequestCount == 2)
            await state.finish(eventID: reviewerID)
        }
        let finalPool = await state.requestPoolSnapshot()
        #expect(finalPool.totalRunning == 0)
        #expect(finalPool.totalWaiting == 0)
    }
}
