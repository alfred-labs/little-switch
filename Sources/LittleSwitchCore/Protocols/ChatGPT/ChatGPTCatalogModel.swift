package struct ChatGPTCatalogModel: Equatable, Sendable {
    package let slug: String
    package let title: String

    package init(slug: String, title: String) {
        self.slug = slug
        self.title = title
    }
}
