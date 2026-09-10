import ArgumentParser
import Foundation
import RepositoryTooling

struct DiagnosticsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diagnostics",
        abstract: "Read aggregate metrics from explicitly selected diagnostic fixtures or logs.",
        subcommands: [SessionToolDefinitionsCommand.self])

    @OptionGroup var options: RepositoryOptions
}

struct SessionToolDefinitionsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "session-tool-defs",
        abstract: "Count MCP definitions in each conversation group's last request.",
        discussion:
            "Groups use model, the first 400 characters of the sorted first-message JSON, "
            + "and builtin tool names. They are heuristic groups, not exact session "
            + "identifiers. Only aggregate metrics are printed."
    )

    @OptionGroup var options: RepositoryOptions

    @Argument(help: "Directory containing traffic-*.jsonl segments.", completion: .directory)
    var logsDirectory: String

    @Option(help: "Known number of mounted tools; prints last_defs/N instead of a dash.")
    var mounted: Int?

    func run() throws {
        let entries = try FileManager.default.contentsOfDirectory(
            at: options.resolve(logsDirectory),
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: .skipsHiddenFiles)
        let files = try entries.compactMap { url -> (url: URL, date: Date)? in
            guard url.lastPathComponent.hasPrefix("traffic-"), url.pathExtension == "jsonl" else { return nil }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values.isRegularFile == true else { return nil }
            return (url, values.contentModificationDate ?? .distantPast)
        }
        let ordered = files.sorted {
            $0.date == $1.date ? $0.url.lastPathComponent < $1.url.lastPathComponent : $0.date < $1.date
        }
        var analyzer = SessionToolDefinitions()
        for file in ordered { try ingest(file.url, into: &analyzer) }
        print(analyzer.report(mounted: mounted), terminator: "")
    }

    private func ingest(_ file: URL, into analyzer: inout SessionToolDefinitions) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var pending = Data()
        while let bytes = try handle.read(upToCount: 64 * 1_024), !bytes.isEmpty {
            pending.append(bytes)
            while let newline = pending.firstIndex(of: 10) {
                analyzer.ingest(Data(pending[..<newline]))
                pending.removeSubrange(...newline)
            }
        }
        if !pending.isEmpty { analyzer.ingest(pending) }
    }
}
