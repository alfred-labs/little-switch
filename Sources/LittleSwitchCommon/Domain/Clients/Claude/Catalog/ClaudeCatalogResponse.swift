import Foundation

public struct ClaudeCatalogResponse: Codable, Equatable, Sendable {
    public var data: [ClaudeCatalogModel]
    public var firstID: String?
    public var lastID: String?
    public var hasMore: Bool

    private enum CodingKeys: String, CodingKey {
        case data
        case firstID = "first_id"
        case lastID = "last_id"
        case hasMore = "has_more"
    }
    package init(
        data: [ClaudeCatalogModel],
        firstID: String? = nil,
        lastID: String? = nil,
        hasMore: Bool
    ) {
        self.data = data
        self.firstID = firstID
        self.lastID = lastID
        self.hasMore = hasMore
    }

}
