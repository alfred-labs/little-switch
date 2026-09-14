import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

actor ManualProviderRequestPoolTiming: ProviderRequestPoolTiming {
    private struct Sleeper {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var instant: Duration = .zero
    private var sleepers: [UUID: Sleeper] = [:]

    func now() -> Duration {
        instant
    }

    func sleep(until deadline: Duration) async throws {
        if deadline <= instant {
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            let _: Void = try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if deadline <= instant {
                    continuation.resume()
                } else {
                    sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                }
            }
        } onCancel: {
            Task {
                await self.cancelSleeper(id: id)
            }
        }
    }

    func advance(by duration: Duration) {
        instant += duration
        let ready = sleepers.filter { $0.value.deadline <= instant }
        for (id, sleeper) in ready {
            sleepers[id] = nil
            sleeper.continuation.resume()
        }
    }

    var sleeperCount: Int {
        sleepers.count
    }

    private func cancelSleeper(id: UUID) {
        guard let sleeper = sleepers.removeValue(forKey: id) else {
            return
        }
        sleeper.continuation.resume(throwing: CancellationError())
    }
}

actor RegistrationCancellationTiming: ProviderRequestPoolTiming {
    private var cancelsOnRead = false

    func now() -> Duration {
        if cancelsOnRead {
            cancelsOnRead = false
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
        }
        return .zero
    }

    func sleep(until _: Duration) async throws {
        try await ContinuousClock().sleep(for: .seconds(300))
    }

    func cancelOnNextRead() {
        cancelsOnRead = true
    }
}

actor SnapshotBlockingTiming: ProviderRequestPoolTiming {
    private var instant: Duration = .zero
    private var shouldBlockNextRead = false
    private var blockedReadValue: Duration?
    private let blockedReadReleased = AsyncTestGate()

    func now() async -> Duration {
        guard shouldBlockNextRead else {
            return instant
        }
        shouldBlockNextRead = false
        let capturedInstant = instant
        blockedReadValue = capturedInstant
        try? await blockedReadReleased.wait()
        blockedReadValue = nil
        return capturedInstant
    }

    func sleep(until _: Duration) async throws {
        try await ContinuousClock().sleep(for: .seconds(300))
    }

    func blockNextRead(at instant: Duration) {
        self.instant = instant
        shouldBlockNextRead = true
    }

    func setInstant(_ instant: Duration) {
        self.instant = instant
    }

    func waitUntilReadIsBlocked() async throws {
        let _: Bool = try await eventually(
            description: "the provider request pool timing read to block"
        ) {
            await self.isReadBlocked ? true : nil
        }
    }

    func releaseBlockedRead() async {
        await blockedReadReleased.open()
    }

    private var isReadBlocked: Bool {
        blockedReadValue != nil
    }
}

enum ProviderRequestPoolTestIDs {
    static let alpha = UUID(
        uuid: (0x10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)
    )
    static let beta = UUID(
        uuid: (0x10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2)
    )
}

func providerRequestPoolConfiguration(
    alphaLimit: Int = 2,
    betaLimit: Int? = nil,
    alphaRevision: UInt64 = 0,
    betaRevision: UInt64 = 0,
    providerOrder: [UUID]? = nil,
    alphaName: String = "Alpha",
    betaName: String = "Beta",
    routes: [ProviderRequestRouteKey: ProviderRequestRouteTarget]? = nil
) -> ProviderRequestPoolConfiguration {
    let alpha = ProviderRequestPoolProviderConfiguration(
        id: ProviderRequestPoolTestIDs.alpha,
        displayName: alphaName,
        maximumParallelRequests: alphaLimit,
        revision: alphaRevision
    )
    let beta = ProviderRequestPoolProviderConfiguration(
        id: ProviderRequestPoolTestIDs.beta,
        displayName: betaName,
        maximumParallelRequests: betaLimit ?? 2,
        revision: betaRevision
    )
    let providersByID = [alpha.id: alpha, beta.id: beta]
    let order = providerOrder ?? (betaLimit == nil ? [alpha.id] : [alpha.id, beta.id])
    let defaultRoutes: [ProviderRequestRouteKey: ProviderRequestRouteTarget] = [
        ProviderRequestRouteKey(client: .claude, modelIdentifier: "claude-alpha"):
            ProviderRequestRouteTarget(providerID: alpha.id, modelID: "alpha-model"),
        ProviderRequestRouteKey(client: .codex, modelIdentifier: "codex-alpha"):
            ProviderRequestRouteTarget(providerID: alpha.id, modelID: "alpha-model"),
        ProviderRequestRouteKey(client: .claude, modelIdentifier: "claude-beta"):
            ProviderRequestRouteTarget(providerID: beta.id, modelID: "beta-model"),
    ]
    return ProviderRequestPoolConfiguration(
        providers: order.compactMap { providersByID[$0] },
        routes: routes ?? defaultRoutes
    )
}

func providerRequestAdmission(
    eventID: UUID = UUID(),
    providerID: UUID = ProviderRequestPoolTestIDs.alpha,
    providerRevision: UInt64 = 0,
    client: GatewayClient = .claude,
    modelIdentifier: String = "claude-alpha",
    targetModelID: String = "alpha-model",
    retainedBodyBytes: Int = 1
) -> ProviderRequestAdmission {
    ProviderRequestAdmission(
        eventID: eventID,
        providerID: providerID,
        providerRevision: providerRevision,
        client: client,
        modelIdentifier: modelIdentifier,
        targetModelID: targetModelID,
        retainedBodyBytes: retainedBodyBytes
    )
}

enum ProviderRequestAdmissionOutcome: Equatable, Sendable {
    case admitted
    case failed(GatewayAdmissionError)
    case cancelled
}

struct ProviderRequestPoolGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

struct MachineWaiter: Sendable {
    let admission: ProviderRequestAdmission
    let task: Task<ProviderRequestAdmissionOutcome, Never>
}

struct MachineProvider: Sendable {
    let id: UUID
    var displayName: String
    var limit: Int
    var revision: UInt64
    let modelIdentifier: String
    let baseTargetModelID: String
    var targetModelID: String
    var isConfigured: Bool
    var active: [UUID: ProviderRequestAdmission] = [:]
    var waiting: [MachineWaiter] = []
}

struct MachineState: Sendable {
    var reference: [UUID: MachineProvider]
    let timing: ManualProviderRequestPoolTiming
    var removedOrder: [UUID] = []
}

let machineProviderOrder = [
    ProviderRequestPoolTestIDs.alpha,
    ProviderRequestPoolTestIDs.beta,
]

func providerRequestAdmissionTask(
    pool: ProviderRequestPool,
    admission: ProviderRequestAdmission
) -> Task<ProviderRequestAdmissionOutcome, Never> {
    Task {
        do {
            try await pool.admit(admission)
            return .admitted
        } catch is CancellationError {
            return .cancelled
        } catch let error as GatewayAdmissionError {
            return .failed(error)
        } catch {
            Issue.record("Unexpected admission error: \(error)")
            return .cancelled
        }
    }
}

func waitForProviderRequestPoolSnapshot(
    _ pool: ProviderRequestPool,
    timeout: Duration = .seconds(5),
    where predicate: @escaping @Sendable (ProviderRequestPoolSnapshot) -> Bool
) async throws -> ProviderRequestPoolSnapshot {
    try await eventually(
        timeout: timeout,
        description: "the provider request pool to reach the expected state"
    ) {
        let snapshot = await pool.snapshot()
        return predicate(snapshot) ? snapshot : nil
    }
}

func waitForProviderRequestPoolSleeperCount(
    _ timing: ManualProviderRequestPoolTiming,
    _ expectedCount: Int,
    timeout: Duration = .seconds(5)
) async throws {
    let _: Int = try await eventually(
        timeout: timeout,
        description: "the provider request pool timing to reach \(expectedCount) sleepers"
    ) {
        let actualCount = await timing.sleeperCount
        return actualCount == expectedCount ? actualCount : nil
    }
}
