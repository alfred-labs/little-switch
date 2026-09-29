import Foundation
import LittleSwitchWire

/// The owning connection keeps its admitted projection as values, without
/// capturing a responder, credentials, or mutable capability observations.
package enum ResponsesSteeringProjection: Equatable, Sendable {
    case native
    case managed(providerID: UUID, acceptsImages: Bool)

    func validate(_ steering: ResponsesWebSocketSteering, model: String) throws {
        typealias InputKey = OpenAIResponsesRequestEnvelope.Key
        let original = JSONValue.array(steering.input)
        let fields: JSONObject = [
            OpenAIResponsesRoutingRequest.Key.model.rawValue: .string(model),
            InputKey.input.rawValue: original,
        ]
        let body = try JSONValue.object(fields).serializedData()
        do {
            let projected: Data
            switch self {
            case .native:
                projected = try ResponsesChatCompletionsReasoning.nativeRequestBody(
                    ResponsesProviderState.normalize(body: body, providerID: nil))
            // swift-format keeps each associated-value binding local.
            // swiftlint:disable:next pattern_matching_keywords
            case .managed(let providerID, let acceptsImages):
                let normalized = try ResponsesProviderState.normalize(
                    body: ResponsesProviderState.degradedBody(body), providerID: providerID)
                let images = try ResponsesImageInputProjection.project(body: normalized, acceptsImages: acceptsImages)
                let namespaced = try OpenAIResponsesNativeNamespacing.normalize(images.body)
                projected = try ResponsesChatCompletionsReasoning.nativeRequestBody(
                    namespaced.body, providerID: providerID)
            }
            guard try JSONValue.parse(projected).object?[InputKey.input.rawValue] == original else {
                throw Self.invalidInput()
            }
        } catch {
            throw Self.invalidInput()
        }
    }

    private static func invalidInput() -> ResponsesWebSocketFailure {
        .init(
            status: 400,
            code: .invalidInput,
            message: "Steering input requires projection for this response's provider or model",
            parameter: OpenAIResponsesRequestEnvelope.Key.input.rawValue)
    }
}
