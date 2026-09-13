import SwiftSyntax

/// Declaration names and signatures survive whitespace and line movement.
/// Parameter defaults and declaration bodies intentionally do not form identity.
enum MagicStringAnchor {
    static func enclosing(_ syntax: some SyntaxProtocol) -> String {
        var components: [String] = []
        var current = Syntax(syntax).parent
        while let node = current {
            if let name = declarationName(node) { components.insert(name, at: 0) }
            current = node.parent
        }
        return components.isEmpty ? "<file>" : components.joined(separator: "/")
    }

    private static func declarationName(_ node: Syntax) -> String? {
        if let declaration = node.as(StructDeclSyntax.self) { return "struct " + declaration.name.text }
        if let declaration = node.as(EnumDeclSyntax.self) { return "enum " + declaration.name.text }
        if let declaration = node.as(ClassDeclSyntax.self) { return "class " + declaration.name.text }
        if let declaration = node.as(ActorDeclSyntax.self) { return "actor " + declaration.name.text }
        if let declaration = node.as(ProtocolDeclSyntax.self) { return "protocol " + declaration.name.text }
        if let declaration = node.as(ExtensionDeclSyntax.self) {
            return "extension " + normalized(declaration.extendedType)
                + (declaration.genericWhereClause.map(normalized) ?? "")
        }
        if let declaration = node.as(FunctionDeclSyntax.self) {
            return memberKind(declaration.modifiers) + "func " + declaration.name.text
                + (declaration.genericParameterClause.map(normalized) ?? "")
                + signature(declaration.signature)
                + (declaration.genericWhereClause.map(normalized) ?? "")
        }
        if let declaration = node.as(InitializerDeclSyntax.self) {
            return "init" + (declaration.optionalMark?.text ?? "")
                + (declaration.genericParameterClause.map(normalized) ?? "")
                + signature(declaration.signature)
                + (declaration.genericWhereClause.map(normalized) ?? "")
        }
        if node.is(DeinitializerDeclSyntax.self) { return "deinit" }
        if let declaration = node.as(SubscriptDeclSyntax.self) {
            return memberKind(declaration.modifiers) + "subscript"
                + (declaration.genericParameterClause.map(normalized) ?? "")
                + parameters(declaration.parameterClause) + normalized(declaration.returnClause)
                + (declaration.genericWhereClause.map(normalized) ?? "")
        }
        if let binding = node.as(PatternBindingSyntax.self) {
            let declaration = node.parent?.parent?.as(VariableDeclSyntax.self)
            return memberKind(declaration?.modifiers) + "binding " + normalized(binding.pattern)
        }
        return nil
    }

    private static func memberKind(_ modifiers: DeclModifierListSyntax?) -> String {
        modifiers?.first { ["static", "class"].contains($0.name.text) }.map { $0.name.text + " " } ?? ""
    }

    private static func signature(_ signature: FunctionSignatureSyntax) -> String {
        parameters(signature.parameterClause)
            + (signature.effectSpecifiers.map(normalized) ?? "")
            + (signature.returnClause.map(normalized) ?? "")
    }

    private static func parameters(_ clause: FunctionParameterClauseSyntax) -> String {
        "(" + clause.parameters.map { $0.firstName.text + ":" + normalized($0.type) }.joined(separator: ",") + ")"
    }

    private static func normalized(_ node: some SyntaxProtocol) -> String {
        node.tokens(viewMode: .sourceAccurate).map(\.text).joined()
    }
}
