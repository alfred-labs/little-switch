import Foundation
import LittleSwitchCommon

package enum WebSearchTraceContent: Equatable, Sendable {
    case results([WebSearchResult])
    case error(String)
}

package struct WebSearchTrace: Equatable, Sendable {
    let toolUseID: String
    let query: String
    let content: WebSearchTraceContent
    let publicContentJSON: Data?

    package init(
        toolUseID: String,
        query: String,
        content: WebSearchTraceContent,
        publicContentJSON: Data? = nil
    ) {
        self.toolUseID = toolUseID
        self.query = query
        self.content = content
        self.publicContentJSON = publicContentJSON
    }
}
