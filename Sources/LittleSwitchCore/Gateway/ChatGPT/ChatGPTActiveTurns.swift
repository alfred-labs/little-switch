import Foundation

package actor ChatGPTActiveTurns {
    package struct Key: Hashable, Sendable {
        package let owner: String
        package let conversationID: String

        package static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.owner == rhs.owner && lhs.conversationID == rhs.conversationID
        }

        package func hash(into hasher: inout Hasher) {
            hasher.combine(owner)
            hasher.combine(conversationID)
        }
    }

    package enum Failure: Swift.Error, Equatable {
        case busy
        case capacity
        case stopped
    }

    private let maximumActive: Int
    private var tasks: [Key: Task<Void, Never>] = [:]
    private var stopped = false

    package init(maximumActive: Int = 16) { self.maximumActive = maximumActive }

    package func start(
        key: Key,
        operation: @escaping @Sendable () async -> Void
    ) throws -> Task<Void, Never> {
        guard !stopped else { throw Failure.stopped }
        guard tasks[key] == nil else { throw Failure.busy }
        guard tasks.count < maximumActive else { throw Failure.capacity }
        // The actor installs ownership before its child can enter operation.
        // Cancellation is therefore available even while history/admission waits.
        let task = Task {
            await operation()
            tasks[key] = nil
        }
        tasks[key] = task
        return task
    }

    package func cancel(key: Key) { tasks[key]?.cancel() }

    package func shutdown() async {
        stopped = true
        let running = Array(tasks.values)
        for task in running { task.cancel() }
        for task in running { await task.value }
    }
}
