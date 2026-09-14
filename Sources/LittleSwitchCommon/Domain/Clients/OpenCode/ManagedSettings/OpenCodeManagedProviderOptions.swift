import Foundation

public struct OpenCodeManagedProviderOptions: Codable, Equatable, Sendable {
    public var baseURL: String
    public var apiKey: String

    public init(baseURL: String, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }
}
