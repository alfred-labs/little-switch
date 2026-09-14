/// One search hit, provider-neutral: what every web-search bridge projects
/// into the model-facing result list.
public struct WebSearchResult: Codable, Equatable, Sendable {
    public var title: String
    public var url: String
    public var content: String

    public init(title: String, url: String, content: String) {
        self.title = title
        self.url = url
        self.content = content
    }
}
