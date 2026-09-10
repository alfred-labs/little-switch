import Foundation

package protocol ProviderRequestPoolTiming: Sendable {
    func now() async -> Duration
    func sleep(until deadline: Duration) async throws
}

package struct ContinuousProviderRequestPoolTiming: ProviderRequestPoolTiming {
    private let clock = ContinuousClock()
    private let origin: ContinuousClock.Instant

    package init() {
        origin = clock.now
    }

    package func now() async -> Duration {
        origin.duration(to: clock.now)
    }

    package func sleep(until deadline: Duration) async throws {
        try await clock.sleep(until: origin.advanced(by: deadline))
    }
}
