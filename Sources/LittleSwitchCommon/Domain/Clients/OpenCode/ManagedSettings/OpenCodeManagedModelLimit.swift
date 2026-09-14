import Foundation

public struct OpenCodeManagedModelLimit: Codable, Equatable, Sendable {
    public var context: Int?
    public var output: Int

    public init(context: Int? = nil, output: Int) {
        self.context = context
        self.output = output
    }
}
