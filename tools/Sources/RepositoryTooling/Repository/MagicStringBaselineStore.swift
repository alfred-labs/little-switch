import Foundation

enum MagicStringBaselineStore {
    /// Every committed removal is permanent. Intersecting the snapshots that
    /// touched this path checks dirty edits and clean commits against history.
    /// No Git metadata means a standalone fixture/export; incomplete Git history
    /// cannot establish whether the visible baseline is its first introduction.
    static func committed(root: URL) throws -> MagicStringBaseline? {
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path) else { return nil }
        let shallow = try git(["rev-parse", "--is-shallow-repository"], root: root)
        guard shallow == Data("false\n".utf8) else {
            throw RepositoryPolicyError(issues: [
                "Complete Git history is required for the magic string baseline; "
                    + "fetch the full history (git fetch --unshallow) before checking a shallow clone"
            ])
        }
        let path = MagicStringPolicy.baselinePath
        let history = try git(["rev-list", "--full-history", "HEAD", "--", path], root: root)
        let revisions = try revisionIDs(in: history)
        var allowed: Set<MagicStringBaseline.Occurrence>?
        for revision in revisions {
            let entry = try git(["ls-tree", "--name-only", String(revision), "--", path], root: root)
            let baseline =
                entry.isEmpty
                ? MagicStringBaseline(violations: [])
                : try MagicStringBaseline(data: git(["show", "\(revision):" + path], root: root))
            let occurrences = Set(baseline.occurrences)
            allowed = allowed.map { $0.intersection(occurrences) } ?? occurrences
        }
        return allowed.map { MagicStringBaseline(occurrences: Array($0)) }
    }

    static func revisionIDs(in output: Data) throws -> [Substring] {
        guard let history = String(data: output, encoding: .utf8) else {
            throw RepositoryPolicyError(issues: ["Invalid magic string baseline Git history"])
        }
        return history.split(separator: "\n")
    }

    private static func git(_ arguments: [String], root: URL) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["--no-optional-locks", "-C", root.path] + arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = try output.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw RepositoryPolicyError(issues: ["Unable to read the committed magic string baseline history"])
        }
        return data
    }
}
