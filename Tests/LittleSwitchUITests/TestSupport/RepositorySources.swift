import Foundation
import Testing

/// Source-policy tests must follow the repository, not their directory depth.
enum RepositorySources {
    static let root: URL = {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        preconditionFailure("Cannot locate the application package from its test sources")
    }()

    static func uiFiles() throws -> [URL] {
        let sources = root.appendingPathComponent("Sources/LittleSwitchUI")
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: sources, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]))
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        try #require(!files.isEmpty, "UI source policies must inspect the nested production sources")
        return files.sorted { $0.path < $1.path }
    }
}
