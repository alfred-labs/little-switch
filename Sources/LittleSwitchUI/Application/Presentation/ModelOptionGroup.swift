import Foundation

public struct ModelOptionGroup: Equatable, Identifiable, Sendable {
    public var providerID: UUID
    public var providerName: String
    public var options: [ModelOption]

    public var id: UUID { providerID }
}
