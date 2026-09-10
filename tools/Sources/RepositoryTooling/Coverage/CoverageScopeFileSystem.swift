import Foundation

extension CoverageScope {
    package static func load(
        root: URL,
        manifestPath: String = "tools/ci/swift-coverage-exclusions.tsv"
    ) throws -> CoverageScope {
        try CoverageSourcePath.validateRelative(manifestPath, location: "coverage exclusion manifest")
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let sourcesRoot = root.appendingPathComponent("Sources", isDirectory: true)
        let sourceType = try itemType(sourcesRoot, missing: "production source directory is missing: Sources")
        guard sourceType != .typeSymbolicLink else {
            throw CoverageValidationError("production source directory must not be a symbolic link: Sources")
        }
        guard sourceType == .typeDirectory else {
            throw CoverageValidationError("production source path is not a directory: Sources")
        }
        let sources = try discover(directory: sourcesRoot, relativePath: "Sources")
        let manifestURL = root.appendingPathComponent(manifestPath)
        let manifestType = try itemType(manifestURL, missing: "coverage exclusion manifest is missing: \(manifestPath)")
        guard manifestType != .typeSymbolicLink else {
            throw CoverageValidationError("coverage exclusion manifest must not be a symbolic link: \(manifestPath)")
        }
        guard manifestType == .typeRegular else {
            throw CoverageValidationError("coverage exclusion manifest is not a regular file: \(manifestPath)")
        }
        // Parent links would let a package-relative manifest escape its declared root.
        var parent = root
        for component in manifestPath.split(separator: "/").dropLast() {
            parent.appendPathComponent(String(component))
            guard try itemType(parent, missing: "coverage manifest directory is missing") != .typeSymbolicLink else {
                throw CoverageValidationError(
                    "coverage exclusion manifest directory must not be a symbolic link: \(manifestPath)")
            }
        }
        let contents = try String(contentsOf: manifestURL, encoding: .utf8)
        let exclusions = try CoverageExclusionManifest.parse(contents, path: manifestPath)
        return try CoverageScope(sources: sources, exclusions: exclusions, manifestPath: manifestPath)
    }

    private static func discover(directory: URL, relativePath: String) throws -> [String] {
        var sources: [String] = []
        for entry in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let path = relativePath + "/" + entry.lastPathComponent
            let type = try FileManager.default.attributesOfItem(atPath: entry.path)[.type] as? FileAttributeType
            guard type != .typeSymbolicLink else {
                throw CoverageValidationError("symbolic link is not allowed under Sources/: \(path)")
            }
            if type == .typeDirectory {
                sources += try discover(directory: entry, relativePath: path)
            } else if type == .typeRegular, entry.lastPathComponent.hasSuffix(".swift") {
                guard !CoverageSourcePath.containsControl(path) else {
                    throw CoverageValidationError(
                        "discovered source path contains a control character: \(String(reflecting: path))")
                }
                sources.append(path)
            }
        }
        return sources
    }

    private static func itemType(_ url: URL, missing message: String) throws -> FileAttributeType? {
        do {
            return try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
        } catch CocoaError.fileReadNoSuchFile {
            throw CoverageValidationError(message)
        }
    }
}
