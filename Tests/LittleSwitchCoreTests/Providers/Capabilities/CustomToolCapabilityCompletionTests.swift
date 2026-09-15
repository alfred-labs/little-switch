import Foundation
import LittleSwitchCommon
import Testing

import struct os.OSAllocatedUnfairLock

@testable import LittleSwitchCore

@Suite("Custom capability publication window")
struct CustomToolCapabilityCompletionTests {
    @Test("A caller joining a completed probe before publication shares its result")
    @available(macOS 26.0, *)
    func completedFlightJoin() async throws {
        let clock = CustomCapabilityJoiningClock()
        let cache = CustomToolCapabilityCache { clock.now() }
        let key = customCapabilityKey()
        clock.joinOnRead {
            // accept() reads the clock on the cache actor before publishing evidence.
            // An immediate task joins this completed flight without a scheduler race.
            cache.assumeIsolated { isolatedCache in
                let completedInline = OSAllocatedUnfairLock(initialState: false)
                let task = Task.immediate {
                    let mode = try await isolatedCache.mode(for: key) {
                        Issue.record("A completed flight must satisfy the joining caller without another probe")
                        return .functionEnvelope
                    }
                    completedInline.withLock { $0 = true }
                    return mode
                }
                #expect(completedInline.withLock { $0 })
                return task
            }
        }
        #expect(try await cache.mode(for: key) { .native } == .native)
        let joining = try #require(clock.joinedTask)
        #expect(try await joining.value == .native)
        #expect(await cache.waiterCount == 0)
        #expect(await cache.activeProbeCount == 0)
        #expect(try await cache.mode(for: key) { .inconclusive } == .native)
    }
}

private final class CustomCapabilityJoiningClock: Sendable {
    private typealias ProbeTask = Task<CustomToolCapabilityMode, any Error>
    private let operation = OSAllocatedUnfairLock<(@Sendable () -> ProbeTask)?>(initialState: nil)
    private let joined = OSAllocatedUnfairLock<ProbeTask?>(initialState: nil)

    var joinedTask: Task<CustomToolCapabilityMode, any Error>? { joined.withLock { $0 } }

    func joinOnRead(_ value: @escaping @Sendable () -> Task<CustomToolCapabilityMode, any Error>) {
        operation.withLock { $0 = value }
    }

    func now() -> Date {
        let join = operation.withLock { value in
            defer { value = nil }
            return value
        }
        if let join {
            let task = join()
            joined.withLock { $0 = task }
        }
        return Date(timeIntervalSince1970: 1_700_000_000)
    }
}
