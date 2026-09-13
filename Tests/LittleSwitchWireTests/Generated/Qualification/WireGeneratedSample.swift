// Generated codec qualification support. Do not edit.
import LittleSwitchWire

public struct WireGeneratedSample: Sendable {
    public let name: String
    public let input: String
    public let expectedError: WireCodingError?
    public let operation: @Sendable (JSONValue) throws -> JSONValue
}
