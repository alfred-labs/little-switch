import Foundation

public struct OpenCodeManagedModel: Codable, Equatable, Sendable {
    public var name: String
    public var limit: OpenCodeManagedModelLimit?
    public var modalities: OpenCodeManagedModelModalities?

    public init(
        name: String,
        limit: OpenCodeManagedModelLimit? = nil,
        modalities: OpenCodeManagedModelModalities? = nil
    ) {
        self.name = name
        self.limit = limit
        self.modalities = modalities
    }
}
