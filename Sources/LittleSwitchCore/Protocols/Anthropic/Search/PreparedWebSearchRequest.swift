import Foundation
import LittleSwitchCommon

package struct PreparedWebSearchRequest: Equatable, Sendable {
    let upstreamBody: Data
    let originalModel: String
    let streaming: Bool
    let maximumUses: Int
    let searchOptions: WebSearchFilterOptions
    package let privateToolName: String?

    package init(
        upstreamBody: Data,
        originalModel: String,
        streaming: Bool,
        maximumUses: Int,
        searchOptions: WebSearchFilterOptions = WebSearchFilterOptions(),
        privateToolName: String? = "web_search"
    ) {
        self.upstreamBody = upstreamBody
        self.originalModel = originalModel
        self.streaming = streaming
        self.maximumUses = maximumUses
        self.searchOptions = searchOptions
        self.privateToolName = privateToolName
    }
}
