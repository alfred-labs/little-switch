import Foundation
import SwiftOperators
import SwiftParser
import SwiftSyntax

/// Finds string literals that directly enter a user-visible presentation API.
///
/// This is intentionally narrower than "every string in the UI target": keys,
/// system-image names, paths, and model values are not display copy. The
/// scanner reports only the argument or assignment position that SwiftUI or
/// AppKit renders as user-facing text.
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
        let folded = (try? OperatorTable.standardOperators.foldAll(parsed).cast(SourceFileSyntax.self)) ?? nil
        let tree = folded ?? parsed
        let converter = SourceLocationConverter(fileName: filePath, tree: tree)
        let visitor = UserVisibleStringVisitor(filePath: filePath, converter: converter)
        visitor.walk(tree)
        return visitor.findings
    }

    package static func scan(directory: URL) throws -> [Finding] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        var findings: [Finding] = []
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        while let element = enumerator?.nextObject() {
            guard let url = element as? URL, url.pathExtension == "swift" else { continue }
            // Swift source files must be UTF-8; decoding avoids failing the whole scan on one file.
            // swiftlint:disable:next optional_data_string_conversion
            let source = String(decoding: try Data(contentsOf: url), as: UTF8.self)
            let resolvedDirectory = directory.standardizedFileURL.resolvingSymlinksInPath().path
            let resolvedURL = url.standardizedFileURL.resolvingSymlinksInPath()
            let relative =
                resolvedURL.path
                .replacingOccurrences(of: resolvedDirectory + "/", with: "")
            findings.append(contentsOf: scan(source: source, filePath: relative))
        }
        return findings.sorted { ($0.file, $0.line, $0.column) < ($1.file, $1.line, $1.column) }
    }
}

private final class UserVisibleStringVisitor: SyntaxVisitor {
    private static let firstArgumentAPIs: Set<String> = [
        "Text", "Label", "Button", "TextField", "SecureField", "Toggle",
        "Picker", "ProgressView", "Stepper", "GroupBox", "Menu", "SettingsSection",
        "SettingsSectionHeader", "SettingsMappingRow",
    ]
    private static let modifierAPIs: Set<String> = [
        "help", "accessibilityLabel", "navigationTitle", "alert", "confirmationDialog",
    ]
    private static let titleAssignments: Set<String> = [
        "messageText", "informativeText", "title",
    ]
    private static let labeledDisplayArguments: Set<String> = [
        "subtitle", "prompt", "detail",
    ]
    private static let labeledTitleInitializers: [String: String] = [
        "NSMenuItem": "NSMenuItem(title:)",
        "NSMenu": "NSMenu(title:)",
        "NSStatusItem": "NSStatusItem(title:)",
        "NSWindow": "NSWindow(title:)",
    ]

    private let filePath: String
    private let converter: SourceLocationConverter
    private(set) var findings: [UserVisibleStringScanner.Finding] = []

    init(filePath: String, converter: SourceLocationConverter) {
        self.filePath = filePath
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        recordAppKitArguments(in: node)
    }

    private func recordAppKitArguments(in node: FunctionCallExprSyntax) {
        if let calledName = node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
            Self.firstArgumentAPIs.contains(calledName),
            let argument = node.arguments.first,
            argument.label == nil
        {
            recordDisplayLiterals(in: argument.expression, api: calledName)
        }

        if let member = node.calledExpression.as(MemberAccessExprSyntax.self) {
            let memberName = member.declName.baseName.text
            if Self.modifierAPIs.contains(memberName),
                let argument = node.arguments.first,
                argument.label == nil
            {
                recordDisplayLiterals(in: argument.expression, api: memberName)
            }
        }

        for (type, api) in Self.labeledTitleInitializers {
            recordLabeledAppKitArgument(in: node, label: "title", type: type, api: api)
        }
        recordLabeledAppKitArgument(in: node, label: "withTitle", type: "addButton", api: "addButton(withTitle:)")

        for argument in node.arguments {
            guard let label = argument.label?.text,
                Self.labeledDisplayArguments.contains(label)
            else { continue }
            let api = label == "prompt" ? "prompt" : label
            recordDisplayLiterals(in: argument.expression, api: api)
        }
    }

    override func visitPost(_ node: InfixOperatorExprSyntax) {
        // After SwiftOperators folding, `x.title = y` becomes
        // InfixOperatorExprSyntax with an assignment operator child.
        guard node.operator.as(AssignmentExprSyntax.self) != nil else { return }
        guard let member = node.leftOperand.as(MemberAccessExprSyntax.self),
            Self.titleAssignments.contains(member.declName.baseName.text)
        else { return }
        recordDisplayLiterals(in: node.rightOperand, api: member.declName.baseName.text)
    }

    override func visitPost(_ node: SequenceExprSyntax) {
        // Unfolded assignments (if the folder is skipped) still reach this
        // visitor as a three-element sequence.
        let elements = Array(node.elements)
        if elements.count == 3,
            elements[1].as(AssignmentExprSyntax.self) != nil,
            let member = elements[0].as(MemberAccessExprSyntax.self),
            Self.titleAssignments.contains(member.declName.baseName.text)
        {
            recordDisplayLiterals(in: elements[2], api: member.declName.baseName.text)
            return
        }
        for (index, element) in elements.enumerated() {
            guard index + 2 < elements.count,
                let member = element.as(MemberAccessExprSyntax.self),
                Self.titleAssignments.contains(member.declName.baseName.text)
            else { continue }
            recordDisplayLiterals(in: elements[index + 2], api: member.declName.baseName.text)
        }
    }

    private func recordLabeledAppKitArgument(
        in node: FunctionCallExprSyntax,
        label: String,
        type: String,
        api: String
    ) {
        let calledExpressionName: String?
        if let reference = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            calledExpressionName = reference.baseName.text
        } else if let member = node.calledExpression.as(MemberAccessExprSyntax.self) {
            calledExpressionName = member.declName.baseName.text
        } else {
            calledExpressionName = nil
        }
        guard calledExpressionName == type else { return }
        guard let argument = node.arguments.first(where: { $0.label?.text == label }),
            let literal = argument.expression.as(StringLiteralExprSyntax.self)
        else { return }
        guard !isEmptyLiteral(literal) else { return }
        record(literal, api: api)
    }

    /// Walks an arbitrary expression (direct literal, ternary, or nested
    /// container) and records every string literal inside it.
    private func recordDisplayLiterals(in expression: ExprSyntax, api: String) {
        if let literal = expression.as(StringLiteralExprSyntax.self), isEmptyLiteral(literal) {
            return
        }
        if let literal = expression.as(StringLiteralExprSyntax.self) {
            record(literal, api: api)
        } else {
            for node in expression.children(viewMode: .sourceAccurate) {
                recordDisplayLiterals(in: Syntax(node), api: api)
            }
        }
    }

    private func recordDisplayLiterals(in node: Syntax, api: String) {
        if let literal = node.as(StringLiteralExprSyntax.self), isEmptyLiteral(literal) {
            return
        }
        if let literal = node.as(StringLiteralExprSyntax.self) {
            record(literal, api: api)
        } else {
            for child in node.children(viewMode: .sourceAccurate) {
                recordDisplayLiterals(in: child, api: api)
            }
        }
    }

    private func isEmptyLiteral(_ literal: StringLiteralExprSyntax) -> Bool {
        literal.segments.allSatisfy {
            guard case .stringSegment(let segment) = $0 else { return false }
            return segment.content.text.isEmpty
        }
    }

    private func record(_ literal: StringLiteralExprSyntax, api: String) {
        let location = converter.location(for: literal.positionAfterSkippingLeadingTrivia)
        findings.append(
            UserVisibleStringScanner.Finding(
                file: filePath,
                line: location.line,
                column: location.column,
                api: api,
                text: literal.representedLiteralValue ?? rawInterpolatedText(of: literal),
                staticSegments: staticSegments(of: literal)
            ))
    }

    private func staticSegments(of literal: StringLiteralExprSyntax) -> [String] {
        literal.segments.compactMap { segment -> String? in
            guard case .stringSegment(let segmentSyntax) = segment else { return nil }
            let value = segmentSyntax.content.text
            return value.isEmpty ? nil : value
        }
    }

    private func rawInterpolatedText(of literal: StringLiteralExprSyntax) -> String {
        let description = literal.trimmedDescription
        guard description.count >= 2, description.hasPrefix("\""), description.hasSuffix("\"") else {
            return description
        }
        return String(description.dropFirst().dropLast())
    }
}
