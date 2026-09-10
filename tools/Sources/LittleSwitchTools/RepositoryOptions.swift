import ArgumentParser
import Foundation

struct RepositoryOptions: ParsableArguments {
    @Option(
        help: "Repository root for relative paths (default: the invocation directory).",
        completion: .directory
    )
    var root: String?

    func resolve(_ path: String) -> URL {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let repositoryRoot =
            root.map { URL(fileURLWithPath: $0, isDirectory: true, relativeTo: currentDirectory) }
            ?? currentDirectory
        return URL(fileURLWithPath: path, relativeTo: repositoryRoot).standardizedFileURL
    }
}
