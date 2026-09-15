import Foundation
import LittleSwitchCommon
import LittleSwitchWire

package enum ModelImageProbeResponse {
    package static let maximumBytes = 32 * 1_024

    package static func classify(
        body: Data,
        status: Int,
        wire: ModelImageInputWire,
        expectedColors: [String]
    ) -> ModelImageInputProbeOutcome {
        guard body.count <= maximumBytes else { return .inconclusive(.sizeLimit) }
        if status == 404 || status == 405 { return .inconclusive(.routeUnavailable) }
        guard (200..<300).contains(status) else {
            return ModelImageInputRejection.matches(status: status, body: body, hasImageInput: true)
                ? .unsupported : .inconclusive(.httpStatus(status))
        }
        do {
            let root = try ModelImageProbeResponseBody.fields(body: body, wire: wire)
            guard root["error"] == nil || root["error"] is NSNull else { return .inconclusive(.invalidResponse) }
            let text: String
            switch wire {
            case .responses:
                guard let status = root["status"] as? String else { return .inconclusive(.invalidResponse) }
                guard status == "completed" else { return .inconclusive(.incompleteResponse) }
                guard let output = root["output"] as? [[String: Any]] else { return .inconclusive(.invalidResponse) }
                text = output.filter { $0["type"] as? String == "message" && $0["role"] as? String == "assistant" }
                    .flatMap { $0["content"] as? [[String: Any]] ?? [] }
                    .filter { $0["type"] as? String == "output_text" }
                    .compactMap { $0["text"] as? String }
                    .joined(separator: " ")
            case .chatCompletions:
                guard let choices = root["choices"] as? [[String: Any]], choices.count == 1,
                    let choice = choices.first,
                    let message = choice["message"] as? [String: Any], message["role"] as? String == "assistant"
                else { return .inconclusive(.invalidResponse) }
                guard choice["finish_reason"] as? String == "stop" else { return .inconclusive(.incompleteResponse) }
                text = message["content"] as? String ?? ""
            }
            let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
            let colors = text.lowercased().components(separatedBy: separators).filter { !$0.isEmpty }
            return colors == expectedColors ? .verified : .inconclusive(.wrongAnswer)
        } catch ModelImageProbeResponseBody.Error.incomplete {
            return .inconclusive(.incompleteResponse)
        } catch {
            return .inconclusive(.invalidResponse)
        }
    }

    package static func usage(body: Data, wire: ModelImageInputWire) -> ResponsesUsage? {
        guard body.count <= maximumBytes,
            let root = try? ModelImageProbeResponseBody.fields(body: body, wire: wire),
            let fields = root["usage"] as? [String: Any], let json = try? WireJSONCompatibility.value(fields)
        else { return nil }
        switch wire {
        case .responses:
            guard let usage = try? OpenAIResponsesWireUsage(wireJSON: json),
                usage.inputTokens != nil, usage.outputTokens != nil
            else { return nil }
            return try? responsesWireUsage(usage)
        case .chatCompletions:
            guard let usage = try? OpenAIChatStreamUsage(wireJSON: json) else { return nil }
            return try? chatWireUsage(usage)
        }
    }
}
