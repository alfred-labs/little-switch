public struct OpenCodeManagedModelLimit: Codable, Equatable, Sendable {
    public var context: Int?
    public var output: Int

    public init(context: Int? = nil, output: Int) {
        self.context = context
        self.output = output
    }
}

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

public struct OpenCodeManagedProviderOptions: Codable, Equatable, Sendable {
    public var baseURL: String
    public var apiKey: String

    public init(baseURL: String, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }
}

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

public struct OpenCodeManagedSettings: Codable, Equatable, Sendable {
    public enum Error: Swift.Error, Equatable {
        case noExposedModel
    }

    public static let providerID = "little-switch"

    public var model: String
    public var provider: OpenCodeManagedProvider
    /// Presence records MCP ownership; legacy journals decode a missing value as nil.
    public var mcp: OpenCodeManagedMCPServer?

    public init(
        model: String,
        provider: OpenCodeManagedProvider,
        mcp: OpenCodeManagedMCPServer? = nil
    ) {
        self.model = model
        self.provider = provider
        self.mcp = mcp
    }

    public static func resolve(
        providers: [Provider],
        codex: CodexConfiguration,
        configuration: OpenCodeConfiguration
    ) throws -> OpenCodeManagedSettings {
        let targets = configuration.availableModels(in: providers, codex: codex)
        guard !targets.isEmpty else {
            throw Error.noExposedModel
        }
        let defaultTarget =
            targets.first { $0.mapping == configuration.defaultModel }
            ?? targets.first { $0.mapping == codex.defaultModel }
            ?? targets[0]

        let models = Dictionary(
            uniqueKeysWithValues: targets.map { target in
                (
                    CodexCatalog.slug(for: target),
                    OpenCodeManagedModel(
                        name: target.displayName,
                        limit: limit(for: target.model),
                        modalities: OpenCodeManagedModelModalities(
                            input: target.provider.imageInputsAccepted(for: target.model)
                                ? ["text", "image"] : ["text"],
                            output: ["text"]
                        )
                    )
                )
            }
        )
        return OpenCodeManagedSettings(
            model: "\(providerID)/\(CodexCatalog.slug(for: defaultTarget))",
            provider: OpenCodeManagedProvider(
                npm: "@ai-sdk/openai",
                name: ProductIdentity.displayName,
                options: OpenCodeManagedProviderOptions(
                    baseURL: "https://127.0.0.1:11436/v1",
                    apiKey: ProductIdentity.gatewayAPIKey
                ),
                models: models
            ),
            mcp: .littleSwitch
        )
    }

    private static func limit(for model: DiscoveredModel) -> OpenCodeManagedModelLimit? {
        guard let output = model.maxTokens, output > 0 else {
            return nil
        }
        let context = model.effectiveContextWindow.flatMap { $0 > 0 ? $0 : nil }
        return OpenCodeManagedModelLimit(context: context, output: output)
    }
}
