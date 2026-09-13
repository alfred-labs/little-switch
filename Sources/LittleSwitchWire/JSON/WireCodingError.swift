public struct WireCodingError: Error, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case invalidJSON
        case missingField
        case unexpectedNull
        case typeMismatch
        case invalidDiscriminator
        case additionalFieldCollision
        case unrepresentableNumber
    }

    public let kind: Kind
    public let path: [String]

    public init(_ kind: Kind, path: [String] = []) {
        self.kind = kind
        self.path = path
    }

    func prepending(_ component: String) -> Self {
        Self(kind, path: [component] + path)
    }
}
