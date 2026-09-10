import Darwin
import Foundation
import LittleSwitchCore

package struct ApplicationProcessIdentity: Sendable, Hashable, Comparable {
    package let processIdentifier: pid_t
    package let launchDate: Date

    package init(processIdentifier: pid_t, launchDate: Date) {
        self.processIdentifier = processIdentifier
        self.launchDate = launchDate
    }

    package static func < (
        lhs: ApplicationProcessIdentity,
        rhs: ApplicationProcessIdentity
    ) -> Bool {
        if lhs.launchDate != rhs.launchDate {
            return lhs.launchDate < rhs.launchDate
        }
        return lhs.processIdentifier < rhs.processIdentifier
    }
}

package enum ApplicationHandoffOutcome: Sendable, Equatable {
    case owner
    case superseded
}

package struct ApplicationTerminationState: Sendable, Equatable {
    package private(set) var mode = ApplicationShutdownMode.userQuit

    package init() {}

    package mutating func request(_ requestedMode: ApplicationShutdownMode) {
        if requestedMode == .handoff {
            mode = .handoff
        }
    }
}

package enum ApplicationHandoffError: Swift.Error, Sendable, Equatable {
    case timedOut([ApplicationProcessIdentity])
}

package enum ApplicationHandoffSignal: Sendable, Equatable {
    case handoff
    case terminate
    case kill

    fileprivate var value: Int32 {
        switch self {
        case .handoff:
            SIGUSR1
        case .terminate:
            SIGTERM
        case .kill:
            SIGKILL
        }
    }
}

package protocol ApplicationProcessDiscovering: Sendable {
    func instances() async -> [ApplicationProcessIdentity]
}

package protocol ApplicationProcessSignaling: Sendable {
    func send(
        _ signal: ApplicationHandoffSignal,
        to identity: ApplicationProcessIdentity
    ) async
}

package protocol ApplicationHandoffTiming: Sendable {
    func now() async -> Duration
    func sleep(for duration: Duration) async throws
}

package struct ApplicationHandoffPolicy: Sendable {
    package var handoffTimeout: Duration
    package var terminateTimeout: Duration
    package var killTimeout: Duration
    package var pollInterval: Duration
    package var requiredEmptySnapshots: Int

    package init(
        handoffTimeout: Duration = .seconds(5),
        terminateTimeout: Duration = .seconds(30),
        killTimeout: Duration = .seconds(5),
        pollInterval: Duration = .milliseconds(100),
        requiredEmptySnapshots: Int = 2
    ) {
        self.handoffTimeout = handoffTimeout
        self.terminateTimeout = terminateTimeout
        self.killTimeout = killTimeout
        self.pollInterval = pollInterval
        self.requiredEmptySnapshots = max(1, requiredEmptySnapshots)
    }
}

package struct ApplicationHandoffCoordinator: Sendable {
    private enum Stage: Int, Sendable {
        case handoff
        case terminate
        case kill

        var signal: ApplicationHandoffSignal {
            switch self {
            case .handoff: .handoff
            case .terminate: .terminate
            case .kill: .kill
            }
        }

        func timeout(in policy: ApplicationHandoffPolicy) -> Duration {
            switch self {
            case .handoff: policy.handoffTimeout
            case .terminate: policy.terminateTimeout
            case .kill: policy.killTimeout
            }
        }

        var next: Stage? {
            Stage(rawValue: rawValue + 1)
        }
    }

    private let current: ApplicationProcessIdentity
    private let discovery: any ApplicationProcessDiscovering
    private let signaler: any ApplicationProcessSignaling
    private let timing: any ApplicationHandoffTiming
    private let policy: ApplicationHandoffPolicy

    package init(
        current: ApplicationProcessIdentity,
        discovery: any ApplicationProcessDiscovering,
        signaler: any ApplicationProcessSignaling,
        timing: any ApplicationHandoffTiming,
        policy: ApplicationHandoffPolicy = ApplicationHandoffPolicy()
    ) {
        self.current = current
        self.discovery = discovery
        self.signaler = signaler
        self.timing = timing
        self.policy = policy
    }

    package func acquireOwnership() async throws -> ApplicationHandoffOutcome {
        var stage = Stage.handoff
        var deadline = await timing.now() + stage.timeout(in: policy)
        var signaled = Set<ApplicationProcessIdentity>()
        var emptySnapshots = 0

        while !Task.isCancelled {
            let others = Set(await discovery.instances()).filter { $0 != current }
            try Task.checkCancellation()
            if others.contains(where: { $0 > current }) {
                return .superseded
            }
            let older = others.filter { $0 < current }.sorted()
            if older.isEmpty {
                emptySnapshots += 1
                if emptySnapshots >= policy.requiredEmptySnapshots {
                    return .owner
                }
            } else {
                emptySnapshots = 0
                for identity in older where signaled.insert(identity).inserted {
                    try Task.checkCancellation()
                    await signaler.send(stage.signal, to: identity)
                    try Task.checkCancellation()
                }
            }

            let now = await timing.now()
            try Task.checkCancellation()
            if now >= deadline, !older.isEmpty {
                guard let next = stage.next else {
                    throw ApplicationHandoffError.timedOut(older)
                }
                stage = next
                deadline = now + stage.timeout(in: policy)
                signaled.removeAll(keepingCapacity: true)
                continue
            }
            try await timing.sleep(for: policy.pollInterval)
        }
        throw CancellationError()
    }
}

package struct POSIXApplicationProcessSignaler: ApplicationProcessSignaling {
    package typealias IdentityLookup =
        @Sendable (pid_t) async -> ApplicationProcessIdentity?
    package typealias SignalSender = @Sendable (pid_t, Int32) -> Int32

    private let identityForPID: IdentityLookup
    private let sendSignal: SignalSender

    package init(
        identityForPID: @escaping IdentityLookup,
        sendSignal: @escaping SignalSender
    ) {
        self.identityForPID = identityForPID
        self.sendSignal = sendSignal
    }

    package func send(
        _ signal: ApplicationHandoffSignal,
        to identity: ApplicationProcessIdentity
    ) async {
        guard await identityForPID(identity.processIdentifier) == identity else {
            return
        }
        guard !Task.isCancelled else { return }
        _ = sendSignal(identity.processIdentifier, signal.value)
    }
}
