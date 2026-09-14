import Foundation

public struct CodexTruncationPolicy: Encodable, Equatable, Sendable {
    public var mode: String
    public var limit: Int

    public init(mode: String, limit: Int) {
        self.mode = mode
        self.limit = limit
    }
}
