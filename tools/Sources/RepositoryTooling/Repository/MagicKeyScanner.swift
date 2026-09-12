import Foundation
import SwiftParser
import SwiftSyntax

/// Scans Swift source files for string literals used as dictionary
/// subscript keys or dictionary literal keys — the "magic string" pattern
/// that should come from central protocol field constants instead.
package enum MagicKeyScanner {
    package struct Violation {
        package let file: String
        package let line: Int
        package let column: Int
        package let key: String
        package let kind: String

        package var description: String {
            "\(file):\(line):\(column): raw key \"\(key)\" (\(kind))"
        }
    }

    /// Scans a single Swift source string and returns all violations.
    package static func scan(source: String, filePath: String) -> [Violation] {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: tree)
        let visitor = MagicKeyVisitor(filePath: filePath, converter: converter)
        visitor.walk(tree)
        return visitor.violations
    }

    /// Scans a directory of Swift files recursively and returns violations
    /// whose key is not present in the allowlist.
    package static func scan(directory: URL, allowlist: Set<String> = []) throws -> [Violation] {
        var violations: [Violation] = []
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return violations }
        let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil)
        while let element = enumerator?.nextObject() {
            guard let url = element as? URL, url.pathExtension == "swift" else { continue }
            // Node's former text scan repaired invalid UTF-8; decoding keeps that tolerance.
            // swiftlint:disable:next optional_data_string_conversion
            let source = String(decoding: try Data(contentsOf: url), as: UTF8.self)
            let resolvedDirectory = directory.standardizedFileURL.resolvingSymlinksInPath().path
            let resolvedURL = url.standardizedFileURL.resolvingSymlinksInPath()
            let relative =
                resolvedURL.path
                .replacingOccurrences(of: resolvedDirectory + "/", with: "")
            let fileViolations = scan(source: source, filePath: relative)
            violations.append(contentsOf: fileViolations)
        }
        return
            violations
            .filter { !allowlist.contains($0.key) }
            .sorted { ($0.file, $0.line, $0.column) < ($1.file, $1.line, $1.column) }
    }

    /// Loads an allowlist from a text file (one key per line, `#` comments).
    package static func loadAllowlist(from url: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: url),
            let text = String(data: data, encoding: .utf8)
        else {
            return []
        }
        return Set(
            text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        )
    }
}

private final class MagicKeyVisitor: SyntaxVisitor {
    private let filePath: String
    private let converter: SourceLocationConverter
    private(set) var violations: [MagicKeyScanner.Violation] = []

    init(filePath: String, converter: SourceLocationConverter) {
        self.filePath = filePath
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    /// Detects `someDict["key"]` — subscript access with a string literal key.
    override func visitPost(_ node: SubscriptCallExprSyntax) {
        for argument in node.arguments {
            if let literal = argument.expression.as(StringLiteralExprSyntax.self) {
                record(literal, kind: "subscript")
            }
        }
    }

    /// Detects `["key": value]` — dictionary literal with a string literal key.
    override func visitPost(_ node: DictionaryExprSyntax) {
        guard case .elements(let list) = node.content else { return }
        for element in list {
            if let literal = element.key.as(StringLiteralExprSyntax.self) {
                record(literal, kind: "dict-literal")
            }
        }
    }

    private func record(_ literal: StringLiteralExprSyntax, kind: String) {
        let key = literal.representedLiteralValue ?? "<interpolated>"
        let location = converter.location(for: literal.positionAfterSkippingLeadingTrivia)
        violations.append(
            MagicKeyScanner.Violation(
                file: filePath,
                line: location.line,
                column: location.column,
                key: key,
                kind: kind
            ))
    }
}
