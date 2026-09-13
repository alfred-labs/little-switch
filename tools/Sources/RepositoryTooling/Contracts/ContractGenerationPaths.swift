import Foundation

enum ContractGenerationPaths {
    static let outputRoots = ["Sources/LittleSwitchWire/Generated", "Tests/LittleSwitchWireTests/Generated"]
    static let manifest = "schemas/generated-swift.json"

    static func output(_ path: String, root: URL) throws -> URL {
        guard outputRoots.contains(where: { path.hasPrefix($0 + "/") }), path.hasSuffix(".swift") else {
            throw failure(path, "Output must be a Swift file in an owned Generated directory")
        }
        return try relative(path, root: root)
    }

    static func relative(_ path: String, root: URL) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.hasPrefix("/"), !path.contains("\\"), !components.isEmpty,
            !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
        else {
            throw failure(path, "Unsafe relative path")
        }
        let canonical = root.resolvingSymlinksInPath().standardizedFileURL
        let url = canonical.appendingPathComponent(path)
        var ancestor = canonical
        for component in components {
            ancestor.appendPathComponent(String(component))
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: ancestor.path)) != nil {
                throw failure(path, "Symbolic links are forbidden in generated paths")
            }
        }
        guard url.path.hasPrefix(canonical.path + "/") else { throw failure(path, "Path escapes the repository") }
        return url
    }

    static func failure(_ path: String, _ reason: String) -> ContractGenerationError {
        ContractGenerationError(contract: "generation", pointer: path, reason: reason)
    }
}
