import Foundation

enum CoverageReportPaths {
    static func commonDirectory(first: String, remaining: ArraySlice<String>) -> String {
        var components = Array(first.split(separator: "/").dropLast())
        for source in remaining {
            let directory = source.split(separator: "/").dropLast()
            while !directory.starts(with: components) { components.removeLast() }
        }
        return components.joined(separator: "/") + "/"
    }

    // llvm-cov strips a common directory when reporting multiple sources, but
    // prints the absolute mapped path for a single source. Only names derived
    // from the entire measured scope are accepted; arbitrary basenames are not.
    static func layouts(sources: [String], commonDirectory: String, rootPath: String?) -> [[String]] {
        var layouts = [
            sources.map(relativeSource),
            sources.map { String($0.unicodeScalars.dropFirst(commonDirectory.unicodeScalars.count)) },
        ]
        if let rootPath {
            let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            layouts.append(sources.map { root.appendingPathComponent($0).path })
        }
        return layouts
    }

    static func relativeSource(_ source: String) -> String {
        String(source.unicodeScalars.dropFirst("Sources/".unicodeScalars.count))
    }
}
