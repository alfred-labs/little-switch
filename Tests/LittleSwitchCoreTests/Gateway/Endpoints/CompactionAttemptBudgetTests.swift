import Testing

@testable import LittleSwitchCore

struct CompactionAttemptBudgetTests {
    @Test("Each cause can be consumed once and no sixth upstream call is admitted")
    func bounds() throws {
        var budget = CompactionAttemptBudget()
        budget = try budget.recordingCall()
        for retry in [CompactionAttemptBudget.Retry.routeFallback, .imageFallback, .selectionRepair, .contextTrim] {
            budget = try budget.taking(retry).recordingCall()
            #expect(throws: CompactionAttemptBudget.Error.retryAlreadyUsed) { try budget.taking(retry) }
        }
        #expect(budget.upstreamCalls == 5)
        #expect(budget.imageFallbackUsed)
        #expect(throws: CompactionAttemptBudget.Error.callsExhausted) { try budget.recordingCall() }
    }
}
