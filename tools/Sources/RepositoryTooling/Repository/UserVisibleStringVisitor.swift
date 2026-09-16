import SwiftSyntax

/// Selects display argument positions; expressions decide which literals supply their values.
final class UserVisibleStringVisitor: SyntaxVisitor {
    private static let firstArgumentAPIs: Set<String> = [
        "Text", "Label", "Button", "TextField", "SecureField", "Toggle", "Picker", "ProgressView", "Stepper",
        "GroupBox", "Menu", "Section", "LabeledContent", "ContentUnavailableView", "DisclosureGroup",
        "SettingsSection", "SettingsSectionHeader", "SettingsMappingRow",
    ]
    private static let modifierAPIs: Set<String> = [
        "help", "accessibilityLabel", "accessibilityHint", "accessibilityValue", "navigationTitle", "alert",
        "confirmationDialog",
    ]
    private static let titleAssignments: Set<String> = ["messageText", "informativeText", "title"]
    private static let titleInitializers: Set<String> = ["NSMenuItem", "NSMenu", "NSStatusItem", "NSWindow"]
    private static let displayLabels: [String: Set<String>] = [
        "SettingsSection": ["subtitle"], "SettingsSectionHeader": ["subtitle"],
        "TextField": ["prompt"], "SecureField": ["prompt"], "LabeledContent": ["value"],
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
        if let member = node.calledExpression.as(MemberAccessExprSyntax.self) {
            let name = member.declName.baseName.text
            if Self.modifierAPIs.contains(name), let argument = node.arguments.first, argument.label == nil {
                record(argument.expression, api: name)
            }
            if name == "addButton" {
                recordArgument("withTitle", in: node, api: "addButton(withTitle:)")
            }
        }
        guard let name = displayCallName(node.calledExpression) else { return }
        if Self.firstArgumentAPIs.contains(name) {
            recordFirstArgument(in: node, api: name)
        }
        if Self.titleInitializers.contains(name) {
            recordArgument("title", in: node, api: "\(name)(title:)")
        }
        for label in Self.displayLabels[name] ?? [] {
            recordArgument(label, in: node, api: label)
        }
    }

    override func visitPost(_ node: InfixOperatorExprSyntax) {
        guard node.operator.as(AssignmentExprSyntax.self) != nil,
            let member = node.leftOperand.as(MemberAccessExprSyntax.self),
            Self.titleAssignments.contains(member.declName.baseName.text)
        else { return }
        record(node.rightOperand, api: member.declName.baseName.text)
    }

    private func displayCallName(_ expression: ExprSyntax) -> String? {
        if let reference = expression.as(DeclReferenceExprSyntax.self) { return reference.baseName.text }
        guard let member = expression.as(MemberAccessExprSyntax.self),
            let module = member.base?.as(DeclReferenceExprSyntax.self),
            ["SwiftUI", "AppKit"].contains(module.baseName.text)
        else { return nil }
        return member.declName.baseName.text
    }

    private func recordArgument(_ label: String, in node: FunctionCallExprSyntax, api: String) {
        guard let argument = node.arguments.first(where: { $0.label?.text == label }) else { return }
        record(argument.expression, api: api)
    }

    private func recordFirstArgument(in node: FunctionCallExprSyntax, api: String) {
        // Text(verbatim:) explicitly opts out of localization for this value only.
        guard let first = node.arguments.first, first.label == nil else { return }
        record(first.expression, api: api)
    }

    private func record(_ expression: ExprSyntax, api: String) {
        for literal in UserVisibleStringExpression.literals(in: expression) {
            let location = converter.location(for: literal.positionAfterSkippingLeadingTrivia)
            findings.append(
                .init(
                    file: filePath,
                    line: location.line,
                    column: location.column,
                    api: api,
                    text: literal.representedLiteralValue ?? literal.segments.description,
                    staticSegments: literal.segments.compactMap { segment in
                        guard case .stringSegment(let segment) = segment, !segment.content.text.isEmpty else {
                            return nil
                        }
                        return segment.content.text
                    }
                ))
        }
    }
}
