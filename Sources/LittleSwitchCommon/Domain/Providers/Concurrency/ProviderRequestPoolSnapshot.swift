import Foundation

public struct ProviderRequestPoolSnapshot: Equatable, Sendable {
    public var totalRunning: Int
    public var totalWaiting: Int
    public var providers: [ProviderRequestPoolProviderSnapshot]

    public init(
        totalRunning: Int,
        totalWaiting: Int,
        providers: [ProviderRequestPoolProviderSnapshot]
    ) {
        self.totalRunning = totalRunning
        self.totalWaiting = totalWaiting
        self.providers = providers
    }
}
