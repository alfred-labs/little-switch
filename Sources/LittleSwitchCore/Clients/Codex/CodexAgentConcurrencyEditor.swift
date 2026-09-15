import Foundation
import TOMLKit

package enum CodexAgentConcurrencySyntax: String, Codable, Equatable, Sendable {
    case canonical
    case dotted
}

package struct CodexAgentConcurrencyState: Codable, Equatable, Sendable {
    var originalWasPresent: Bool
    // These Codable fields remain part of the persisted journal so replaying
    // an older applied profile preserves its original restoration metadata.
    // periphery:ignore
    var originalValue: Int?
    // periphery:ignore
    var originalSyntax: CodexAgentConcurrencySyntax?
    var originalToken: String?
    var createdAgentsTable: Bool
    var lastManagedValue: Int
    var managedSyntax: CodexAgentConcurrencySyntax
}

package struct CodexAgentConcurrencyValue: Equatable, Sendable {
    var value: Int
    var syntax: CodexAgentConcurrencySyntax
}

package struct CodexAgentConcurrencyEdit: Equatable, Sendable {
    var text: String
    var state: CodexAgentConcurrencyState
}

public enum CodexAgentConcurrencyEditor {
    enum Error: Swift.Error, Equatable, LocalizedError {
        case inlineAgentsTable
        case unsupportedAgentsSyntax
        case legacyAlias
        case nonIntegerManagedValue
        case unsupportedManagedSyntax

        var errorDescription: String? {
            switch self {
            case .inlineAgentsTable:
                CoreL10n.string(
                    "The `agents` entry in ~/.codex/config.toml is an inline table. Rewrite it as an `[agents]` section and try again."
                )
            case .unsupportedAgentsSyntax:
                CoreL10n.string(
                    "The `agents` entry in ~/.codex/config.toml is not a table. Rewrite it as an `[agents]` section and try again."
                )
            case .legacyAlias:
                CoreL10n.string(
                    "The legacy `agents.max_threads` key in ~/.codex/config.toml conflicts with the managed concurrency limit. Remove it and try again."
                )
            case .nonIntegerManagedValue:
                CoreL10n.string(
                    "The `agents.max_concurrent_threads_per_session` value in ~/.codex/config.toml is not an integer. Fix it and try again."
                )
            case .unsupportedManagedSyntax:
                CoreL10n.string(
                    "The `agents.max_concurrent_threads_per_session` assignments in ~/.codex/config.toml conflict. Keep a single one and try again."
                )
            }
        }
    }

    private struct Assignment {
        var lineIndex: Int
        var prefix: String
        var token: String
        var suffix: String
        var value: Int
        var syntax: CodexAgentConcurrencySyntax

        func replacingToken(with replacement: String) -> String {
            prefix + replacement + suffix
        }
    }

    private struct Document {
        var lines: [String]
        var headerIndices: [Int]
        var current: Assignment?
    }

    package static func activating(
        _ text: String,
        maximumConcurrentThreadsPerSession value: Int,
        state previousState: CodexAgentConcurrencyState? = nil
    ) throws -> CodexAgentConcurrencyEdit {
        var document = try document(from: text)
        let original = document.current
        let insertion: (syntax: CodexAgentConcurrencySyntax, createdTable: Bool)
        if let current = document.current {
            document.lines[current.lineIndex] = current.replacingToken(with: String(value))
            insertion = (current.syntax, false)
        } else {
            insertion = insertManagedAssignment(value, into: &document)
        }
        let result = document.lines.joined(separator: "\n")
        _ = try TOMLTable(string: result)

        var state =
            previousState
            ?? CodexAgentConcurrencyState(
                originalWasPresent: original != nil,
                originalValue: original?.value,
                originalSyntax: original?.syntax,
                originalToken: original?.token,
                createdAgentsTable: insertion.createdTable,
                lastManagedValue: value,
                managedSyntax: insertion.syntax
            )
        state.lastManagedValue = value
        state.managedSyntax = insertion.syntax
        return CodexAgentConcurrencyEdit(text: result, state: state)
    }

    package static func restoring(
        _ text: String,
        state: CodexAgentConcurrencyState
    ) throws -> String {
        let parsedDocument: Document
        do {
            parsedDocument = try document(from: text)
        } catch is Error {
            return text
        }
        var document = parsedDocument
        guard let current = document.current,
            current.value == state.lastManagedValue,
            current.syntax == state.managedSyntax
        else {
            return text
        }

        if state.originalWasPresent {
            guard let originalToken = state.originalToken else {
                return text
            }
            document.lines[current.lineIndex] = current.replacingToken(with: originalToken)
        } else {
            document.lines.remove(at: current.lineIndex)
            if state.createdAgentsTable, current.syntax == .canonical {
                removeCreatedAgentsTableIfEmpty(from: &document.lines)
            }
        }
        let result = document.lines.joined(separator: "\n")
        _ = try TOMLTable(string: result)
        return result
    }

    package static func currentValue(in text: String) throws -> CodexAgentConcurrencyValue? {
        try document(from: text).current.map {
            CodexAgentConcurrencyValue(value: $0.value, syntax: $0.syntax)
        }
    }
}

extension CodexAgentConcurrencyEditor {
    private static func document(from text: String) throws -> Document {
        let root = try TOMLTable(string: text)
        let lines = splitLines(text)
        let headers = tableHeaderIndices(in: lines)
        guard let agentsNode = root["agents"] else {
            return Document(lines: lines, headerIndices: headers, current: nil)
        }
        guard agentsNode.type == .table, let agents = agentsNode.table else {
            throw Error.unsupportedAgentsSyntax
        }
        guard !agents.inline else {
            throw Error.inlineAgentsTable
        }
        guard agents["max_threads"] == nil else {
            throw Error.legacyAlias
        }
        guard let managed = agents["max_concurrent_threads_per_session"] else {
            return Document(lines: lines, headerIndices: headers, current: nil)
        }
        guard let value = managed.int else {
            throw Error.nonIntegerManagedValue
        }
        let assignments = assignments(in: lines, headerIndices: headers, value: value)
        guard assignments.count == 1, let current = assignments.first else {
            throw Error.unsupportedManagedSyntax
        }
        return Document(lines: lines, headerIndices: headers, current: current)
    }

    private static func assignments(
        in lines: [String],
        headerIndices: [Int],
        value: Int
    ) -> [Assignment] {
        var result: [Assignment] = []
        let rootEnd = headerIndices.first ?? lines.count
        for index in 0..<rootEnd {
            if let assignment = assignment(
                at: index,
                in: lines,
                syntax: .dotted,
                expectedValue: value
            ) {
                result.append(assignment)
            }
        }
        for headerIndex in headerIndices
        where tablePath(forHeader: lines[headerIndex]) == ["agents"] {
            let end = headerIndices.first { $0 > headerIndex } ?? lines.count
            for index in (headerIndex + 1)..<end {
                if let assignment = assignment(
                    at: index,
                    in: lines,
                    syntax: .canonical,
                    expectedValue: value
                ) {
                    result.append(assignment)
                }
            }
        }
        return result
    }

    private static func assignment(
        at index: Int,
        in lines: [String],
        syntax: CodexAgentConcurrencySyntax,
        expectedValue: Int
    ) -> Assignment? {
        let line = lines[index]
        guard prefixParses(through: index, in: lines),
            let equals = line.firstIndex(of: "=")
        else {
            return nil
        }
        let compactKey = line[..<equals].filter { !$0.isWhitespace }
        let expectedKey =
            syntax == .canonical
            ? "max_concurrent_threads_per_session"
            : "agents.max_concurrent_threads_per_session"
        guard compactKey == expectedKey else {
            return nil
        }

        let afterEquals = line.index(after: equals)
        let comment = line[afterEquals...].firstIndex(of: "#") ?? line.endIndex
        var tokenStart = afterEquals
        while tokenStart < comment, line[tokenStart].isWhitespace {
            tokenStart = line.index(after: tokenStart)
        }
        var tokenEnd = comment
        while tokenEnd > tokenStart {
            let previous = line.index(before: tokenEnd)
            guard line[previous].isWhitespace else {
                break
            }
            tokenEnd = previous
        }
        let token = String(line[tokenStart..<tokenEnd])
        return Assignment(
            lineIndex: index,
            prefix: String(line[..<tokenStart]),
            token: token,
            suffix: String(line[tokenEnd...]),
            value: expectedValue,
            syntax: syntax
        )
    }

    private static func insertManagedAssignment(
        _ value: Int,
        into document: inout Document
    ) -> (syntax: CodexAgentConcurrencySyntax, createdTable: Bool) {
        let assignment = "max_concurrent_threads_per_session = \(value)"
        if let header = document.headerIndices.first(where: {
            tablePath(forHeader: document.lines[$0]) == ["agents"]
        }) {
            let sectionEnd =
                document.headerIndices.first { $0 > header }
                ?? document.lines.count
            var insertion = sectionEnd
            while insertion > header + 1, isBlank(document.lines[insertion - 1]) {
                insertion -= 1
            }
            document.lines.insert(assignment, at: insertion)
            return (.canonical, false)
        }

        let rootEnd = document.headerIndices.first ?? document.lines.count
        let dottedFamily = (0..<rootEnd).filter { index in
            isDottedAgentsAssignment(at: index, in: document.lines)
        }
        if let last = dottedFamily.last {
            document.lines.insert("agents.\(assignment)", at: last + 1)
            return (.dotted, false)
        }

        let nestedAgentsHeader = document.headerIndices.first { index in
            tablePath(forHeader: document.lines[index])?.first == "agents"
        }
        if let nestedAgentsHeader {
            document.lines.insert(contentsOf: ["[agents]", assignment, ""], at: nestedAgentsHeader)
        } else if document.lines == [""] {
            document.lines = ["[agents]", assignment]
        } else {
            var insertion = document.lines.count
            while insertion > 0, document.lines[insertion - 1].isEmpty {
                insertion -= 1
            }
            document.lines.insert(contentsOf: ["", "[agents]", assignment], at: insertion)
        }
        return (.canonical, true)
    }

    private static func isDottedAgentsAssignment(
        at index: Int,
        in lines: [String]
    ) -> Bool {
        let line = lines[index]
        guard prefixParses(through: index, in: lines),
            let equals = line.firstIndex(of: "=")
        else {
            return false
        }
        let compactKey = line[..<equals].filter { !$0.isWhitespace }
        return compactKey.hasPrefix("agents.")
    }

    private static func removeCreatedAgentsTableIfEmpty(from lines: inout [String]) {
        let headers = tableHeaderIndices(in: lines)
        let matchingHeader = headers.first {
            tablePath(forHeader: lines[$0]) == ["agents"]
        }
        let header = matchingHeader.unsafelyUnwrapped
        let end = headers.first { $0 > header } ?? lines.count
        let tableIsEmpty = lines[(header + 1)..<end].allSatisfy {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard tableIsEmpty else {
            return
        }
        lines.remove(at: header)
        if header > 0, lines[header - 1].isEmpty {
            lines.remove(at: header - 1)
        } else if header < lines.count, lines[header].isEmpty {
            lines.remove(at: header)
        }
        if lines.isEmpty {
            lines = [""]
        }
    }

    private static func splitLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func tableHeaderIndices(in lines: [String]) -> [Int] {
        lines.indices.filter { index in
            let candidate = lines[index].trimmingCharacters(in: .whitespaces)
            guard candidate.hasPrefix("["), (try? TOMLTable(string: candidate)) != nil else {
                return false
            }
            return prefixParses(through: index, in: lines)
        }
    }

    private static func prefixParses(through index: Int, in lines: [String]) -> Bool {
        let prefix = lines[...index].joined(separator: "\n")
        return (try? TOMLTable(string: prefix)) != nil
    }

    private static func tablePath(forHeader line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), !trimmed.hasPrefix("[[") else {
            return nil
        }
        var node = try? TOMLTable(string: trimmed)
        var path: [String] = []
        while let item = node, let key = item.keys.first, let child = item[key]?.table {
            path.append(key)
            node = child
        }
        return path
    }
}
