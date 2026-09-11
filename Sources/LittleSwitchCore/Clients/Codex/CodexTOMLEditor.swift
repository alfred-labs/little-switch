import Foundation
import TOMLKit

package struct CodexRootStringState: Codable, Equatable, Sendable {
    var wasPresent: Bool
    var value: String
    var originalAssignment: String?
}

public enum CodexTOMLEditor {
    public enum Error: Swift.Error, Equatable {
        case nonStringRootValue(String)
        case unsupportedRootSyntax(String)
        case unrepresentableString(String)
    }

    public static let providerID = "little-switch"
    public static let providerName = "LittleSwitch"
    /// The gateway as Codex's native OpenAI endpoint: Codex appends
    /// `/responses` to this base URL, landing on the gateway's `/v1/responses`.
    public static let baseURL = "http://127.0.0.1:11436/v1"
    public static let defaultReasoningEffort = "max"
    /// LittleSwitch's external search services require Codex's live mode.
    /// https://learn.chatgpt.com/docs/config-file/config-basic#web-search-mode
    static let defaultWebSearchMode = "live"
    package static let managedRootKeys = [
        "profile",
        "model",
        "openai_base_url",
        "model_catalog_json",
        "model_reasoning_effort",
        "web_search",
    ]

    /// `model_provider` is no longer managed, but activation still replaces
    /// any legacy managed value. Its original state must therefore survive in
    /// the restore journal even though it is not part of the managed shape.
    package static let journaledRootKeys = managedRootKeys + ["model_provider"]

    static func activating(
        _ text: String,
        model: String,
        catalogPath: String,
        webSearchMode: String? = defaultWebSearchMode
    ) throws -> String {
        _ = try table(from: text)
        var result = try removeRootString("profile", from: text)
        // Migration: the provider root and table belong to the pre-native
        // shape. The table removal keeps restorations clean for profiles that
        // never journaled a pre-LittleSwitch state.
        result = try setRootString("model", value: model, in: result)
        result = try removeRootString("model_provider", from: result)
        result = try setRootString("openai_base_url", value: baseURL, in: result)
        result = try setRootString("model_catalog_json", value: catalogPath, in: result)
        result = try setRootString("model_reasoning_effort", value: defaultReasoningEffort, in: result)
        if let webSearchMode {
            result = try setRootString("web_search", value: webSearchMode, in: result)
        }
        result = try removingOwnedProvider(from: result)
        _ = try table(from: result)
        return result
    }

    public static func activating(
        _ text: String,
        signature: CodexManagedProfileSignature,
        catalogPath: String
    ) throws -> String {
        try activating(
            text,
            model: signature.modelSlug,
            catalogPath: catalogPath,
            webSearchMode: signature.webSearchMode
        )
    }

    public static func rootString(_ key: String, in text: String) throws -> String? {
        let root = try table(from: text)
        guard let value = root[key] else {
            return nil
        }
        guard let string = value.string else {
            throw Error.nonStringRootValue(key)
        }
        return string
    }

    public static func string(at path: [String], in text: String) throws -> String? {
        guard !path.isEmpty else {
            return nil
        }
        var current = try table(from: text)
        for component in path.dropLast() {
            guard let nested = current[component]?.table else {
                return nil
            }
            current = nested
        }
        return current[path[path.count - 1]]?.string
    }

    package static func rootState(
        _ key: String,
        in text: String,
        preservingAssignment: Bool = false
    ) throws -> CodexRootStringState {
        let root = try table(from: text)
        guard let value = root[key] else {
            return CodexRootStringState(wasPresent: false, value: "")
        }
        guard let string = value.string else {
            throw Error.nonStringRootValue(key)
        }
        var state = CodexRootStringState(wasPresent: true, value: string)
        if preservingAssignment {
            let lines = splitLines(text)
            guard let index = rootAssignmentIndex(key, in: lines, before: firstTableIndex(in: lines)) else {
                throw Error.unsupportedRootSyntax(key)
            }
            state.originalAssignment = lines[index]
        }
        return state
    }

    package static func restoring(
        _ text: String,
        states: [String: CodexRootStringState]
    ) throws -> String {
        var result = text
        // Key order is irrelevant: every edit targets the root region and is
        // position-independent. Sorting keeps the transformation deterministic.
        for (key, state) in states.sorted(by: { $0.key < $1.key }) {
            if state.wasPresent {
                result = try setRootString(
                    key, value: state.value, in: result, originalAssignment: state.originalAssignment
                )
            } else {
                result = try removeRootString(key, from: result)
            }
        }
        _ = try table(from: result)
        return result
    }

    package static func removingOwnedProvider(from text: String) throws -> String {
        _ = try table(from: text)
        guard
            let range = sectionRange(
                in: text,
                matching: ["model_providers", providerID]
            )
        else {
            return text
        }
        var lines = splitLines(text)
        lines.removeSubrange(range)
        let result = lines.joined(separator: "\n")
        _ = try table(from: result)
        return result
    }

    package static func rootIsManaged(_ text: String, catalogPath: String) throws -> Bool {
        try rootString("openai_base_url", in: text) == baseURL
            && rootString("model_catalog_json", in: text) == catalogPath
    }

    /// The pre-native LittleSwitch profile wrote a custom provider root and
    /// table. Treat it as LittleSwitch-owned too so an upgrade reuses the
    /// existing restore journal instead of journaling managed values.
    package static func rootIsLegacyManaged(_ text: String, catalogPath: String) throws -> Bool {
        _ = catalogPath
        let legacyBaseURL = try string(
            at: ["model_providers", providerID, "base_url"], in: text
        )
        return try rootString("model_provider", in: text) == providerID
            && (legacyBaseURL == baseURL || legacyBaseURL == baseURL + "/")
            && string(at: ["model_providers", providerID, "wire_api"], in: text) == "responses"
    }

    private static func setRootString(
        _ key: String,
        value: String,
        in text: String,
        originalAssignment: String? = nil
    ) throws -> String {
        let root = try table(from: text)
        if let existing = root[key], existing.string == nil {
            throw Error.nonStringRootValue(key)
        }
        var lines = splitLines(text)
        let rootEnd = firstTableIndex(in: lines)
        let assignment: String
        if let originalAssignment {
            let original = try table(from: originalAssignment)
            guard original.keys == [key], original[key]?.string == value else {
                throw Error.unsupportedRootSyntax(key)
            }
            assignment = originalAssignment
        } else {
            assignment = "\(key) = \(try quoted(value))"
        }
        if let index = rootAssignmentIndex(key, in: lines, before: rootEnd) {
            lines[index] = assignment
            return lines.joined(separator: "\n")
        }
        if root[key] != nil {
            throw Error.unsupportedRootSyntax(key)
        }

        var insertion = rootEnd
        while insertion > 0, lines[insertion - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            insertion -= 1
        }
        lines.insert(assignment, at: insertion)
        let nextTable = firstTableIndex(in: lines)
        let needsTableSeparator =
            nextTable > 0
            && !lines[nextTable - 1].trimmingCharacters(in: .whitespaces).isEmpty
        if needsTableSeparator {
            lines.insert("", at: nextTable)
        }
        return lines.joined(separator: "\n")
    }

    private static func removeRootString(_ key: String, from text: String) throws -> String {
        let root = try table(from: text)
        guard let existing = root[key] else {
            return text
        }
        guard existing.string != nil else {
            throw Error.nonStringRootValue(key)
        }
        var lines = splitLines(text)
        let rootEnd = firstTableIndex(in: lines)
        guard let index = rootAssignmentIndex(key, in: lines, before: rootEnd) else {
            throw Error.unsupportedRootSyntax(key)
        }
        lines.remove(at: index)
        return lines.joined(separator: "\n")
    }

    private static func table(from text: String) throws -> TOMLTable {
        try TOMLTable(string: text)
    }

    private static func quoted(_ value: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        var bytes = try encoder.encode(value).map { CChar(bitPattern: $0) }
        bytes.append(0)
        let encoded = String(cString: &bytes)
        guard
            let parsed = try? TOMLTable(string: "value = \(encoded)"),
            parsed["value"]?.string == value
        else {
            throw Error.unrepresentableString(value)
        }
        return encoded
    }

    private static func splitLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func firstTableIndex(in lines: [String]) -> Int {
        tableHeaderIndices(in: lines).first ?? lines.count
    }

    private static func rootAssignmentIndex(
        _ key: String,
        in lines: [String],
        before end: Int
    ) -> Int? {
        lines.indices.prefix(end).first { index in
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                let parsed = try? TOMLTable(string: line)
            else {
                return false
            }
            guard parsed[key] != nil else {
                return false
            }
            // An assignment-looking line can be content inside a multiline
            // string. Only a complete document prefix establishes root scope.
            let prefix = lines[...index].joined(separator: "\n")
            return (try? TOMLTable(string: prefix)) != nil
        }
    }

    private static func sectionRange(
        in text: String,
        matching target: [String]
    ) -> Range<Int>? {
        let lines = splitLines(text)
        let headers = tableHeaderIndices(in: lines)
        guard
            let start = headers.first(where: { tablePath(forHeader: lines[$0]) == target })
        else {
            return nil
        }
        let end = headers.first { $0 > start } ?? lines.count
        return start..<end
    }

    private static func tableHeaderIndices(in lines: [String]) -> [Int] {
        lines.indices.filter { index in
            let candidate = lines[index].trimmingCharacters(in: .whitespaces)
            guard candidate.hasPrefix("["), (try? TOMLTable(string: candidate)) != nil else {
                return false
            }
            let prefix = lines[...index].joined(separator: "\n")
            return (try? TOMLTable(string: prefix)) != nil
        }
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
        return path.isEmpty ? nil : path
    }
}
