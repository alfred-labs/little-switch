import Foundation

public struct CodexReasoningEffortPreset: Encodable, Equatable, Sendable {
    public var effort: String
    public var description: String

    public init(effort: String, description: String) {
        self.effort = effort
        self.description = description
    }
}
