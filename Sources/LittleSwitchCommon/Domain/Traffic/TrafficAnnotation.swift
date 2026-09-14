/// A non-terminal observation recorded on an in-flight request: something
/// was adjusted or dropped before dispatch, worth naming in the log without
/// deciding the request's lifecycle, failure surface, or usage outcome.
public struct TrafficAnnotation: Codable, Equatable, Sendable {
    public var kind: String
    public var message: String

    public init(kind: String, message: String) {
        self.kind = kind
        self.message = message
    }
}
