import Testing

@Suite("Shared deterministic test clock", .timeLimit(.minutes(1)))
struct ResolverTestClockTests {
    @Test("The registration barrier exposes each sleeper before an observer resumes")
    func registrationBarrier() async throws {
        let clock = ResolverTestClock()
        for count in 1...100 {
            let observer = Task {
                try await clock.waitForSleeps(count)
                #expect(await clock.pendingSleeps == 1)
            }
            defer { observer.cancel() }
            let sleeper = Task { try await clock.sleep(until: clock.now.advanced(by: .seconds(1))) }
            defer { sleeper.cancel() }
            try await valueWithinTimeout(observer, description: "registered sleeper observer")
            await clock.advance(by: .seconds(1))
            try await valueWithinTimeout(sleeper, description: "registered sleeper completion")
        }
    }

    @Test("Advancing manual time wakes only due sleepers and cancellation removes the rest")
    func sleepAndCancel() async throws {
        let clock = ResolverTestClock(milliseconds: 100)
        let first = Task { try await clock.sleep(until: clock.now.advanced(by: .seconds(1))) }
        defer { first.cancel() }
        try await clock.waitForSleeps(1)
        let second = Task { try await clock.sleep(until: clock.now.advanced(by: .seconds(2))) }
        defer { second.cancel() }
        try await clock.waitForSleeps(2)
        await clock.advance(by: 1_000)
        try await valueWithinTimeout(first, description: "manual clock first deadline")
        #expect(clock.nowMilliseconds() == 1_100)
        #expect(await clock.pendingSleeps == 1)
        second.cancel()
        await #expect(throws: CancellationError.self) { try await second.value }
        #expect(await clock.pendingSleeps == 0)
        try await clock.sleep(until: clock.now)
    }

    @Test("Concurrent advances are serialized without losing elapsed time")
    func concurrentAdvances() async {
        let clock = ResolverTestClock()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 { group.addTask { await clock.advance(by: 1) } }
        }
        #expect(clock.nowMilliseconds() == 100)
    }
}
