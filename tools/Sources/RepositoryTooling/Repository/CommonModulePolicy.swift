import SwiftParser
import SwiftSyntax

/// Keeps shared domain values independent of implementation targets.
enum CommonModulePolicy {
    private static let sourcePrefix = "Sources/LittleSwitchCommon/"

    static func violations(files: [String: String]) -> [String] {
        let commonSources = files.filter { $0.key.hasPrefix(sourcePrefix) && $0.key.hasSuffix(".swift") }
        var issues: [String] = []
        for (path, source) in commonSources {
            let visitor = CommonImportVisitor(viewMode: .sourceAccurate)
            visitor.walk(Parser.parse(source: source))
            issues += visitor.imports.filter { $0 != "Foundation" }.map {
                "\(path): LittleSwitchCommon must not import \($0)"
            }
        }
        if let manifest = files["Package.swift"] {
            issues += manifestViolations(manifest, hasCommonSources: !commonSources.isEmpty)
        }
        return issues.sorted()
    }

    private static func manifestViolations(_ source: String, hasCommonSources: Bool) -> [String] {
        let visitor = CommonTargetVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: source))
        guard let common = visitor.targets[.common] else {
            return hasCommonSources ? ["Package.swift: missing LittleSwitchCommon target"] : []
        }
        var issues: [String] = []
        if let dependencies = common.arguments.first(where: { $0.label?.text == "dependencies" }) {
            if dependencies.expression.as(ArrayExprSyntax.self)?.elements.isEmpty != true {
                issues.append("Package.swift: LittleSwitchCommon must have no target dependencies")
            }
        }
        for module in [CommonTargetVisitor.Module.core, .search, .ui] {
            guard let target = visitor.targets[module] else { continue }
            let dependencies = target.arguments.first { $0.label?.text == "dependencies" }?
                .expression.as(ArrayExprSyntax.self)
            let names = dependencies?.elements.compactMap { CommonTargetVisitor.literal($0.expression) } ?? []
            if !names.contains(CommonTargetVisitor.Module.common.rawValue) {
                issues.append("Package.swift: \(module.rawValue) must directly depend on LittleSwitchCommon")
            }
        }
        return issues
    }
}

private final class CommonImportVisitor: SyntaxVisitor {
    private(set) var imports: Set<String> = []

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        if let module = node.path.first?.name.text {
            imports.insert(module)
        }
        return .skipChildren
    }
}

private final class CommonTargetVisitor: SyntaxVisitor {
    enum Module: String {
        case common = "LittleSwitchCommon"
        case core = "LittleSwitchCore"
        case search = "LittleSwitchSearch"
        case ui = "LittleSwitchUI"
    }

    private(set) var targets: [Module: FunctionCallExprSyntax] = [:]

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
            member.declName.baseName.text == "target",
            let expression = node.arguments.first(where: { $0.label?.text == "name" })?.expression,
            let name = Self.literal(expression), let module = Module(rawValue: name)
        else {
            return .visitChildren
        }
        targets[module] = node
        return .visitChildren
    }

    static func literal(_ expression: ExprSyntax) -> String? {
        guard let literal = expression.as(StringLiteralExprSyntax.self), literal.segments.count == 1,
            let segment = literal.segments.first?.as(StringSegmentSyntax.self)
        else { return nil }
        return segment.content.text
    }
}
