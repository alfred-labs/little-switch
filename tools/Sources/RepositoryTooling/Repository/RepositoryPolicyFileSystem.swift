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
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        var visitor = Visitor(root: root)
        try visitor.visit(root, relative: "")
        return Snapshot(files: visitor.files, paths: visitor.paths)
    }

    private struct Visitor {
        private let rootComponents: [String]
        private let skipped: Set<String> = [
            ".build", ".claude", ".git", ".superpowers", ".swiftpm", "build", "dist", "node_modules",
        ]
        private var activeDirectories: Set<String> = []
        private(set) var files: [String: String] = [:]
        private(set) var paths = Set<String>()

        init(root: URL) {
            rootComponents = root.pathComponents
        }

        mutating func visit(_ directory: URL, relative: String) throws {
            let currentPath = directory.standardizedFileURL.resolvingSymlinksInPath().path
            guard activeDirectories.insert(currentPath).inserted else {
                return
            }
            defer { activeDirectories.remove(currentPath) }
            for entry in try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) {
                guard !skipped.contains(entry.lastPathComponent) else { continue }
                let path =
                    relative.isEmpty
                    ? entry.lastPathComponent
                    : relative + "/" + entry.lastPathComponent
                let resolved = entry.standardizedFileURL.resolvingSymlinksInPath()
                paths.insert(path)
                // Links are repository entries, but another checkout owns their external targets.
                guard resolved.pathComponents.starts(with: rootComponents) else { continue }
                let resolvedType =
                    try FileManager.default.attributesOfItem(
                        atPath: resolved.path
                    )[.type] as? FileAttributeType
                if resolvedType == .typeDirectory {
                    try visit(resolved, relative: path)
                } else if resolvedType == .typeRegular {
                    // Node's former text scan repaired invalid UTF-8, including binary resources.
                    // swiftlint:disable:next optional_data_string_conversion
                    files[path] = String(decoding: try Data(contentsOf: resolved), as: UTF8.self)
                }
            }
        }

    }
}
