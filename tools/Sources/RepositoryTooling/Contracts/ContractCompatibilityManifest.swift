import Foundation

struct ContractCompatibilityManifest: Decodable {
    let formatVersion: Int
    let overrides: [ContractCompatibilityRule]

    static func read(_ data: Data) throws -> Self {
        do { return try decode(data) } catch let error as ContractGenerationError { throw error } catch {
            throw failure("Invalid compatibility manifest: \(error)")
        }
    }

    private static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(ContractSchemaValue.self, from: data)
        guard let object = value.object, Set(object.keys) == ["formatVersion", "overrides"],
            let rules = object["overrides"]?.array
        else { throw failure("Invalid compatibility manifest") }
        let allowed: Set<String> = [
            "id", "root", "projection", "pointer", "operation", "reason", "source", "fixtures",
            "values", "schema", "required",
        ]
        for rule in rules {
            guard let fields = rule.object, Set(fields.keys).isSubset(of: allowed) else {
                throw failure("Unknown compatibility option")
            }
        }
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.formatVersion == 1, Set(result.overrides.map(\.id)).count == result.overrides.count else {
            throw failure("Unsupported compatibility version or repeated rule ID")
        }
        for rule in result.overrides {
            guard
                [rule.id, rule.root, rule.projection, rule.pointer, rule.reason, rule.source]
                    .allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                !rule.fixtures.isEmpty, rule.fixtures.allSatisfy({ !$0.isEmpty })
            else { throw failure("Compatibility rules require identity, reason, provenance and fixtures") }
            guard rule.operation == .enumValues || rule.values == nil,
                rule.operation == .additionalField || (rule.schema == nil && rule.required == nil)
            else { throw failure("Compatibility payload does not match its operation") }
        }
        return result
    }

    private static func failure(_ reason: String) -> ContractGenerationError {
        ContractGenerationError(contract: "compatibility", reason: reason)
    }
}

struct ContractCompatibilityRule: Decodable {
    enum Operation: String, Decodable { case optional, nullable, enumValues, openEnum, additionalField }
    let id: String
    let root: String
    let projection: String
    let pointer: String
    let operation: Operation
    let reason: String
    let source: String
    let fixtures: [String]
    let values: [String]?
    let schema: ContractSchemaValue?
    let required: Bool?
}
