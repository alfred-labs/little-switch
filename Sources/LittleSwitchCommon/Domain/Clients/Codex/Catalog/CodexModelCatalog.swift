import Foundation

public struct CodexModelCatalog: Encodable, Equatable, Sendable {
    public var models: [CodexCatalogModel]

    public init(models: [CodexCatalogModel]) {
        self.models = models
    }
}
