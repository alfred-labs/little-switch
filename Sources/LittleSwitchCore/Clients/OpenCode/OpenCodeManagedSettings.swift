import Foundation
import LittleSwitchCommon

extension OpenCodeManagedSettings {
    public static func resolve(
        providers: [Provider],
        codex: CodexConfiguration,
        configuration: OpenCodeConfiguration,
        responsesWireVerdicts: [UUID: Bool] = [:]
    ) throws -> OpenCodeManagedSettings {
        let targets = configuration.availableModels(in: providers, codex: codex)
        guard !targets.isEmpty else {
            throw Error.noExposedModel
        }
        guard Set(targets.map { CodexCatalog.slug(for: $0) }).count == targets.count else {
            throw Error.ambiguousModelIdentifiers
        }
        let defaultTarget =
            targets.first { $0.mapping == configuration.defaultModel }
            ?? targets.first { $0.mapping == codex.defaultModel }
            ?? targets[0]

        let models = Dictionary(
            uniqueKeysWithValues: try targets.map { target in
                let acceptsImages = try ModelImageInputPolicyResolver.acceptsImages(
                    provider: target.provider,
                    model: target.model,
                    wire: ProviderResponsesWireResolver.resolve(
                        provider: target.provider, learnedNative: responsesWireVerdicts[target.provider.id]),
                    observations: target.provider.imageInputObservations)
                return (
                    CodexCatalog.slug(for: target),
                    OpenCodeManagedModel(
                        name: target.displayName,
                        limit: limit(for: target.model),
                        modalities: OpenCodeManagedModelModalities(
                            input: acceptsImages
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
