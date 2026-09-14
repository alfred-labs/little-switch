import Foundation
import LittleSwitchCommon

package struct ResponsesModelTurn: Equatable, Sendable {
    let id: String
    let rootJSON: Data
    let outputJSON: Data
    let usage: ResponsesUsage
    let webSearchCall: ResponsesWebSearchToolCall?
}
