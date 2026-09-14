import Foundation
import LittleSwitchCommon

package struct AnthropicModelTurn: Equatable, Sendable {
    let id: String
    let contentJSON: Data
    let stopReason: String?
    let stopSequenceJSON: Data?
    let usage: AnthropicUsage
    let webSearchCall: WebSearchToolCall?
}
