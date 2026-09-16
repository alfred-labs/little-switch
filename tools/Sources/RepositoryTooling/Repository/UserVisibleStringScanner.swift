import Foundation
import SwiftOperators
import SwiftParser
import SwiftSyntax

/// Finds untranslated literals in known presentation APIs without inferring variable or helper return values.
package enum UserVisibleStringScanner {
    package struct Finding: Equatable, Sendable {
        package let file: String
        package let line: Int
        package let column: Int
        package let api: String
        package let text: String
        package let staticSegments: [String]

        package var description: String {
            "\(file):\(line):\(column): \(api): \"\(text)\""
        }
    }

    package static func scan(source: String, filePath: String) -> [Finding] {
        let parsed = Parser.parse(source: source)
        // An unknown custom operator must not prevent standard operators elsewhere from folding.
        let tree = OperatorTable.standardOperators.foldAll(parsed) { _ in }
        let converter = SourceLocationConverter(fileName: filePath, tree: parsed)
        let visitor = UserVisibleStringVisitor(filePath: filePath, converter: converter)
        visitor.walk(tree)
        return visitor.findings.sorted { ($0.line, $0.column) < ($1.line, $1.column) }
    }

    package static func scan(directory: URL) throws -> [Finding] {
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        guard try FileManager.default.attributesOfItem(atPath: root.path)[.type] as? FileAttributeType == .typeDirectory
        else {
            throw RepositoryPolicyError(issues: ["UI string scan requires a directory: \(directory.path)"])
        }
        return try scanFiles(in: root, relative: "")
            .sorted { ($0.file, $0.line, $0.column) < ($1.file, $1.line, $1.column) }
    }

    private static func scanFiles(in directory: URL, relative: String) throws -> [Finding] {
        var findings: [Finding] = []
        for entry in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let path = relative + entry.lastPathComponent
            let type = try FileManager.default.attributesOfItem(atPath: entry.path)[.type] as? FileAttributeType
            if type == .typeDirectory {
                findings += try scanFiles(in: entry, relative: path + "/")
            } else if type == .typeRegular, entry.pathExtension == "swift" {
                // Preserve the scanner's UTF-8 replacement semantics; I/O errors still fail the scan.
                // swiftlint:disable:next optional_data_string_conversion
                let source = String(decoding: try Data(contentsOf: entry), as: UTF8.self)
                findings += scan(source: source, filePath: path)
            }
            // Symbolic links inside the scan root are not followed.
        }
        return findings
    }
}
