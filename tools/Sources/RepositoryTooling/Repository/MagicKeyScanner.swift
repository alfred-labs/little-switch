import Foundation
import SwiftOperators
import SwiftParser
import SwiftSyntax

/// Syntax-only scan of dictionary keys and catalogued discriminant values.
/// Discriminants require a direct field subscript/member or dictionary key;
/// local variable types and aliases are not inferred. Swift's standard operator
/// table separates comparisons before their literal operands are inspected.
package enum MagicKeyScanner {
    /// Scans a single Swift source string and returns all violations.
    package static func scan(
        source: String, filePath: String, catalogue: MagicStringCatalogue = .empty
    ) -> [Violation] {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: tree)
        let visitor = MagicKeyVisitor(filePath: filePath, converter: converter, catalogue: catalogue)
        let folded = OperatorTable.standardOperators.foldAll(tree) { _ in }
        visitor.walk(folded)
        struct Identity: Hashable {
            let anchor: String
            let rule: RuleID
            let literal: Literal
        }
        var counts: [Identity: Int] = [:]
        return visitor.violations
            .sorted { ($0.position.line, $0.position.column) < ($1.position.line, $1.position.column) }
            .map { violation in
                let identity = Identity(anchor: violation.anchor, rule: violation.rule, literal: violation.literal)
                let ordinal = counts[identity, default: 0] + 1
                counts[identity] = ordinal
                return Violation(
                    file: violation.file,
                    position: violation.position,
                    rule: violation.rule,
                    literal: violation.literal,
                    anchor: violation.anchor,
                    ordinal: ordinal
                )
            }
    }

    /// Scans a directory of Swift files recursively, without exemptions.
    package static func scan(
        directory: URL, catalogue: MagicStringCatalogue = .empty
    ) throws -> [Violation] {
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
            let fileViolations = scan(source: source, filePath: relative, catalogue: catalogue)
            violations.append(contentsOf: fileViolations)
        }
        return
            violations
            .sorted {
                ($0.file, $0.position.line, $0.position.column) < ($1.file, $1.position.line, $1.position.column)
            }
    }
}

private final class MagicKeyVisitor: SyntaxVisitor {
    private let filePath: String
    private let converter: SourceLocationConverter
    private let catalogue: MagicStringCatalogue.Index
    private(set) var violations: [MagicKeyScanner.Violation] = []

    init(filePath: String, converter: SourceLocationConverter, catalogue: MagicStringCatalogue) {
        self.filePath = filePath
        self.converter = converter
        self.catalogue = MagicStringCatalogue.Index(catalogue)
        super.init(viewMode: .sourceAccurate)
    }

    /// Detects `someDict["key"]` — subscript access with a string literal key.
    override func visitPost(_ node: SubscriptCallExprSyntax) {
        guard let argument = node.arguments.first,
            argument.label == nil,
            let literal = argument.expression.as(StringLiteralExprSyntax.self)
        else { return }
        record(literal, rule: .subscriptKey)
    }

    /// Detects `["key": value]` — dictionary literal with a string literal key.
    override func visitPost(_ node: DictionaryExprSyntax) {
        guard case .elements(let list) = node.content else { return }
        for element in list {
            if let literal = element.key.as(StringLiteralExprSyntax.self) {
                record(literal, rule: .dictionaryKey)
            }
            recordDiscriminant(element.value, field: element.key)
        }
    }

    override func visitPost(_ node: InfixOperatorExprSyntax) {
        guard let operation = node.operator.as(BinaryOperatorExprSyntax.self),
            ["==", "!="].contains(operation.operator.text)
        else { return }
        if let field = discriminantField(node.leftOperand) {
            recordDiscriminant(node.rightOperand, field: field)
        }
        if let field = discriminantField(node.rightOperand) {
            recordDiscriminant(node.leftOperand, field: field)
        }
    }

    override func visitPost(_ node: SwitchExprSyntax) {
        guard let field = discriminantField(node.subject) else { return }
        for element in node.cases {
            guard let switchCase = element.as(SwitchCaseSyntax.self),
                let label = switchCase.label.as(SwitchCaseLabelSyntax.self)
            else { continue }
            for item in label.caseItems {
                if let pattern = item.pattern.as(ExpressionPatternSyntax.self) {
                    recordDiscriminant(pattern.expression, field: field)
                }
            }
        }
    }

    private func unwrapped(_ expression: ExprSyntax) -> ExprSyntax {
        if let cast = expression.as(AsExprSyntax.self) { return unwrapped(cast.expression) }
        if let tuple = expression.as(TupleExprSyntax.self) {
            guard tuple.elements.count == 1, let element = tuple.elements.first, element.label == nil else {
                return expression
            }
            return unwrapped(element.expression)
        }
        if let optional = expression.as(OptionalChainingExprSyntax.self) { return unwrapped(optional.expression) }
        return expression
    }

    private func discriminantField(_ expression: ExprSyntax) -> ExprSyntax? {
        let expression = unwrapped(expression)
        if let subscriptCall = expression.as(SubscriptCallExprSyntax.self) {
            guard let argument = subscriptCall.arguments.first, argument.label == nil else { return nil }
            return argument.expression
        }
        if expression.is(MemberAccessExprSyntax.self) { return expression }
        return nil
    }

    private func recordDiscriminant(_ expression: ExprSyntax, field: ExprSyntax) {
        guard let literal = unwrapped(expression).as(StringLiteralExprSyntax.self),
            let value = literal.representedLiteralValue
        else { return }
        let field = unwrapped(field)
        if let key = field.as(StringLiteralExprSyntax.self)?.representedLiteralValue {
            if catalogue.contains(value, key: key, owners: []) { record(literal, rule: .discriminantValue) }
            return
        }
        var names: [String] = []
        var current = field
        while let member = current.as(MemberAccessExprSyntax.self) {
            names.insert(member.declName.baseName.text, at: 0)
            guard let base = member.base else { break }
            current = base
        }
        if let root = current.as(DeclReferenceExprSyntax.self) { names.insert(root.baseName.text, at: 0) }
        if names.last == "rawValue" { names.removeLast() }
        guard let key = names.popLast(), catalogue.contains(value, key: key, owners: names) else { return }
        record(literal, rule: .discriminantValue)
    }

    private func record(_ literal: StringLiteralExprSyntax, rule: MagicKeyScanner.RuleID) {
        let value = MagicKeyScanner.Literal(
            kind: literal.representedLiteralValue == nil ? .interpolated : .string,
            value: literal.representedLiteralValue ?? literal.trimmedDescription
        )
        let location = converter.location(for: literal.positionAfterSkippingLeadingTrivia)
        violations.append(
            MagicKeyScanner.Violation(
                file: filePath,
                position: .init(line: location.line, column: location.column),
                rule: rule,
                literal: value,
                anchor: MagicStringAnchor.enclosing(literal),
                ordinal: 1
            ))
    }
}
