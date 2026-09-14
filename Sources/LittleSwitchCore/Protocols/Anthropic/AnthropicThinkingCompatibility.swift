import Foundation
import LittleSwitchCommon
import LittleSwitchWire

package enum AnthropicThinkingCompatibility {
    /// Adds the provider's fallback only when the caller disabled thinking
    /// without choosing an effort. Every ineligible body retains its bytes.
    package static func applying(
        _ override: ProviderDisabledThinkingOverride,
        to body: Data
    ) throws -> Data {
        guard override == .lowEffort,
            var request = try? WireCodec.decode(AnthropicThinkingRequest.self, from: body).value,
            case .disabled? = request.thinking,
            case .absent = request.reasoningEffort
        else {
            return body
        }
        var output = request.outputConfig ?? AnthropicOutputConfiguration()
        guard case .absent = output.effort else { return body }
        output.effort = .value(.low)
        request.outputConfig = output
        return try WireCodec.encode(request)
    }
}
