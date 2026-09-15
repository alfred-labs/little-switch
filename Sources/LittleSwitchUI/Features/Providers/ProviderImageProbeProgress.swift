import Foundation

public struct ProviderImageProbeProgress: Equatable, Sendable {
    public var completed: Int
    public var total: Int
    public var running: Bool

    public init(completed: Int = 0, total: Int = 0, running: Bool = false) {
        self.completed = completed
        self.total = total
        self.running = running
    }
}

struct ProviderImageProbeBatch: Sendable {
    let token: UUID
    let task: Task<Void, Never>
}
