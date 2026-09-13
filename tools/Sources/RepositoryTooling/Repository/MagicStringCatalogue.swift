import Foundation

/// The extractor's contextual catalogue. This is syntax evidence, not Swift type inference.
package struct MagicStringCatalogue: Decodable, Sendable {
    package struct Property: Decodable, Sendable {
        package let root: String
        package let definition: String
        package let path: String
        package let key: String
    }

    package struct EnumValue: Decodable, Sendable {
        package let root: String
        package let path: String
        package let values: [String]

        private enum CodingKeys: CodingKey { case root, path, values }

        package init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            root = try container.decode(String.self, forKey: .root)
            path = try container.decode(String.self, forKey: .path)
            values = try container.decode([Scalar].self, forKey: .values).compactMap(\.string)
        }

    }

    package let formatVersion: Int
    package let properties: [Property]
    package let enums: [EnumValue]

    package static let empty = Self(formatVersion: 1, properties: [], enums: [])

    private init(formatVersion: Int, properties: [Property], enums: [EnumValue]) {
        self.formatVersion = formatVersion
        self.properties = properties
        self.enums = enums
    }

    package init(data: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
        guard formatVersion == 1 else {
            throw RepositoryPolicyError(issues: ["Unsupported magic string catalogue version \(formatVersion)"])
        }
    }

    struct Index {
        private var generic: [String: Set<String>] = [:]
        private var contextual: [String: [String: Set<String>]] = [:]

        init(_ catalogue: MagicStringCatalogue) {
            let enumerations = Dictionary(grouping: catalogue.enums) { CatalogueLocation(root: $0.root, path: $0.path) }
            generic = Self.closedFields(catalogue.properties, enumerations: enumerations, unqualified: true)
            var owners: [String: [Property]] = [:]
            for property in catalogue.properties {
                for owner in [property.root, property.definition] { owners[owner, default: []].append(property) }
            }
            for (owner, properties) in owners {
                contextual[owner] = Self.closedFields(properties, enumerations: enumerations, unqualified: false)
            }
        }

        private static func closedFields(
            _ properties: [Property], enumerations: [CatalogueLocation: [EnumValue]], unqualified: Bool
        ) -> [String: Set<String>] {
            var fields: [String: Set<String>] = [:]
            for (key, properties) in Dictionary(grouping: properties, by: \.key) {
                // A closed built-in tool name never closes arbitrary payload names.
                if unqualified && key == "name" { continue }
                var allClosed = true
                var combined: Set<String> = []
                for property in properties {
                    guard let records = enumerations[CatalogueLocation(root: property.root, path: property.path)] else {
                        allClosed = false
                        continue
                    }
                    combined.formUnion(records.flatMap(\.values))
                }
                // `type` is a bounded tagged-union heuristic. Explicit owners
                // still preserve open error/configuration types, as does `name`.
                if allClosed || (unqualified && key == "type") { fields[key] = combined }
            }
            return fields
        }

        func contains(_ value: String, key: String, owners: [String]) -> Bool {
            for end in stride(from: owners.count, through: 1, by: -1) {
                for start in 0..<end {
                    let owner = owners[start..<end].joined(separator: ".")
                    if let fields = contextual[owner] { return fields[key]?.contains(value) == true }
                }
            }
            return generic[key]?.contains(value) == true
        }
    }
}

private struct CatalogueLocation: Hashable {
    // Both coordinates participate in synthesized Hashable/Equatable dictionary identity.
    // periphery:ignore
    let root: String
    // periphery:ignore
    let path: String
}

private struct Scalar: Decodable {
    let string: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        string = try? container.decode(String.self)
        guard
            string != nil || container.decodeNil()
                || (try? container.decode(Bool.self)) != nil
                || (try? container.decode(Double.self)) != nil
        else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an enum scalar")
        }
    }
}
