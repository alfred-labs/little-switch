public struct OpenCodeManagedModelModalities: Codable, Equatable, Sendable {
    public var input: [String]
    public var output: [String]

    public init(input: [String], output: [String]) {
        self.input = input
        self.output = output
    }
}
