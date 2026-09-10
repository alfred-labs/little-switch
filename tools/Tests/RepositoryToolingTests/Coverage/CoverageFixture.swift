import Foundation

enum CoverageFixture {
    static let manifest = "tools/ci/swift-coverage-exclusions.tsv"

    static func write(
        at root: URL,
        sources: [String] = ["Sources/App/A.swift"],
        exclusions: String = "",
        manifest: String = manifest
    ) throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        for path in sources {
            let source = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("// fixture\n".utf8).write(to: source)
        }
        let manifestURL = root.appendingPathComponent(manifest)
        try FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(exclusions.utf8).write(to: manifestURL)
    }

    static func report(_ rows: [(String, String)] = [("App/A.swift", "100.00%")], total: String = "100.00%") -> String {
        let values = rows.map { "\($0.0) 1 0 100.00% 1 0 100.00% 1 0 \($0.1) 0 0 -" }
        return
            ([
                "Filename Regions Missed Regions Cover Functions Missed Functions Executed Lines Missed Lines Cover",
                "------------------------------------------------------------",
            ] + values
            + ["TOTAL 1 0 100.00% 1 0 100.00% \(rows.count) 0 \(total) 0 0 -", ""]).joined(separator: "\n")
    }
}
