import Foundation

package struct ResponsesWebSearchToolCall: Equatable, Sendable {
    let callID: String
    let query: String
    var privateToolName = "web_search"
}
