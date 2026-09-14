import Foundation

public struct OpenCodeManagedProvider: Codable, Equatable, Sendable {
    public var npm: String
    public var name: String
    public var options: OpenCodeManagedProviderOptions
    public var models: [String: OpenCodeManagedModel]

    public init(
        npm: String,
        name: String,
        options: OpenCodeManagedProviderOptions,
        models: [String: OpenCodeManagedModel]
    ) {
        self.npm = npm
        self.name = name
        self.options = options
        self.models = models
    }
}
