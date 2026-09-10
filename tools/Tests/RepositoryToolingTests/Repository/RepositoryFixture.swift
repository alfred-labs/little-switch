import Foundation
import Testing

@testable import RepositoryTooling

enum RepositoryFixture {
    static func root(startingAt source: URL = URL(fileURLWithPath: #filePath)) throws -> URL {
        var directory = source.deletingLastPathComponent()
        while directory.path != "/" {
            let plist = directory.appendingPathComponent("packaging/Info.plist")
            let tooling = directory.appendingPathComponent("tools/Package.swift")
            let hasPlist = FileManager.default.fileExists(atPath: plist.path)
            let hasTooling = FileManager.default.fileExists(atPath: tooling.path)
            if hasPlist && hasTooling {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw RepositoryFixtureError.rootNotFound
    }

    static func text(_ path: String) throws -> String {
        try String(contentsOf: root().appendingPathComponent(path), encoding: .utf8)
    }

    static func policyFiles(_ rules: [RepositoryTextRule]) throws -> [String: String] {
        try Dictionary(uniqueKeysWithValues: Set(rules.map(\.path)).map { ($0, try text($0)) })
    }
}

private enum RepositoryFixtureError: Error {
    case rootNotFound
}
