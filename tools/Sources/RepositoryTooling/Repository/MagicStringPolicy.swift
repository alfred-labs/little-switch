import Foundation

package enum MagicStringPolicy {
    package enum BaselineAction { case initialize, prune }

    package static let baselinePath = "tools/magic-string-baseline.json"
    package static let cataloguePath = "schemas/upstream/catalog.json"
    private static let directories = [
        "Sources/LittleSwitchCommon/",
        "Sources/LittleSwitchCore/Protocols/",
        "Sources/LittleSwitchCore/Tools/",
        "Sources/LittleSwitchCore/Gateway/",
    ]

    static func check(files: [String: String], committedBaseline: MagicStringBaseline? = nil) -> [String] {
        var issues: [String] = []
        var catalogue = MagicStringCatalogue.empty
        if let source = files[cataloguePath] {
            do {
                catalogue = try MagicStringCatalogue(data: Data(source.utf8))
            } catch {
                issues.append("Invalid magic string catalogue: \(error.localizedDescription)")
            }
        } else {
            issues.append("Missing magic string catalogue: \(cataloguePath)")
        }
        let violations = scan(files: files, catalogue: catalogue)
        if let source = files[baselinePath] {
            do {
                let baseline = try MagicStringBaseline(data: Data(source.utf8))
                if let committedBaseline { try baseline.assertDecreased(from: committedBaseline) }
                issues.append(contentsOf: baseline.additionalViolations(in: violations).map(\.description))
                let current = MagicStringBaseline(violations: violations)
                let resolvedCount = Set(baseline.occurrences).subtracting(current.occurrences).count
                if resolvedCount > 0 {
                    issues.append(
                        "Magic string baseline has \(resolvedCount) resolved occurrence(s); "
                            + "run mise run --quiet tools:run -- repo magic-strings --update-baseline"
                    )
                }
            } catch {
                issues.append(error.localizedDescription)
            }
        } else {
            issues.append("Missing magic string baseline: \(baselinePath)")
            issues.append(contentsOf: violations.map(\.description))
        }
        return issues
    }

    package static func updateBaseline(root: URL, action: BaselineAction) throws -> Int {
        let snapshot = try RepositoryPolicyFileSystem.read(root: root)
        let committed = try MagicStringBaselineStore.committed(root: root)
        guard let source = snapshot.files[cataloguePath] else {
            throw RepositoryPolicyError(issues: ["Missing magic string catalogue: \(cataloguePath)"])
        }
        let catalogue = try MagicStringCatalogue(data: Data(source.utf8))
        let violations = scan(files: snapshot.files, catalogue: catalogue)
        let currentData = snapshot.files[baselinePath].map { Data($0.utf8) }
        let updated: MagicStringBaseline
        switch action {
        case .initialize:
            guard currentData == nil, committed == nil else {
                throw RepositoryPolicyError(issues: [
                    "Magic string baseline already exists; use --update-baseline to prune it"
                ])
            }
            updated = MagicStringBaseline(violations: violations)
        case .prune:
            guard let currentData else {
                throw RepositoryPolicyError(issues: ["Missing magic string baseline: \(baselinePath)"])
            }
            let current = try MagicStringBaseline(data: currentData)
            if let committed { try current.assertDecreased(from: committed) }
            updated = try current.pruned(to: violations)
        }
        let destination = root.appendingPathComponent(baselinePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try AtomicFileWriter.prepare(contents: updated.encoded(), at: destination, expectedContents: currentData)
            .commit()
        return updated.occurrences.count
    }

    static func scan(files: [String: String], catalogue: MagicStringCatalogue) -> [MagicKeyScanner.Violation] {
        files.sorted { $0.key < $1.key }
            .filter { file in
                file.key.hasSuffix(".swift") && directories.contains { file.key.hasPrefix($0) }
            }
            .flatMap { file in
                MagicKeyScanner.scan(source: file.value, filePath: file.key, catalogue: catalogue)
            }
    }
}
