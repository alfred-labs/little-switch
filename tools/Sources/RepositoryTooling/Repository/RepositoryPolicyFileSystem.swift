import Foundation

package enum RepositoryPolicyFileSystem {
    struct Snapshot {
        let files: [String: String]
        let paths: Set<String>
    }

    package static func check(root: URL) throws {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let snapshot = try read(root: root)
        let issues = RepositoryPolicies.violations(files: snapshot.files, paths: snapshot.paths, rootPath: root.path)
        guard issues.isEmpty else {
            throw RepositoryPolicyError(issues: issues)
        }
        let scope = try CoverageScope.load(root: root)
        guard !scope.all.isEmpty, !scope.measured.isEmpty,
            scope.all.count == scope.measured.count + scope.excluded.count
        else {
            throw RepositoryPolicyError(issues: ["Production Swift coverage must partition a nonempty measured scope"])
        }
    }

    static func read(root: URL) throws -> Snapshot {
        var files: [String: String] = [:]
        var paths = Set<String>()
        try visit(root, relative: "", files: &files, paths: &paths)
        return Snapshot(files: files, paths: paths)
    }

    private static func visit(
        _ directory: URL, relative: String, files: inout [String: String], paths: inout Set<String>
    ) throws {
        let skipped: Set<String> = [
            ".build", ".claude", ".git", ".superpowers", ".swiftpm", "build", "dist", "node_modules",
        ]
        for entry in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            guard !skipped.contains(entry.lastPathComponent) else { continue }
            let path = relative.isEmpty ? entry.lastPathComponent : relative + "/" + entry.lastPathComponent
            paths.insert(path)
            let type = try FileManager.default.attributesOfItem(atPath: entry.path)[.type] as? FileAttributeType
            if type == .typeDirectory {
                try visit(entry, relative: path, files: &files, paths: &paths)
            } else if type == .typeRegular {
                // Node's former text scan repaired invalid UTF-8, including binary resources.
                // swiftlint:disable:next optional_data_string_conversion
                files[path] = String(decoding: try Data(contentsOf: entry), as: UTF8.self)
            }
        }
    }
}
