import SwiftSyntax

/// Follows literals that supply the display value, never conditions or arbitrary call arguments.
enum UserVisibleStringExpression {
    static func literals(in expression: ExprSyntax) -> [StringLiteralExprSyntax] {
        if let literal = expression.as(StringLiteralExprSyntax.self) {
            let empty = literal.segments.allSatisfy {
                guard case .stringSegment(let segment) = $0 else { return false }
                return segment.content.text.isEmpty
            }
            return empty ? [] : [literal]
        }
        if let ternary = expression.as(TernaryExprSyntax.self) {
            return literals(in: ternary.thenExpression) + literals(in: ternary.elseExpression)
        }
        if let infix = expression.as(InfixOperatorExprSyntax.self) {
            guard let operation = infix.operator.as(BinaryOperatorExprSyntax.self),
                ["+", "??"].contains(operation.operator.text)
            else { return [] }
            return literals(in: infix.leftOperand) + literals(in: infix.rightOperand)
        }
        if let tuple = expression.as(TupleExprSyntax.self) {
            guard tuple.elements.count == 1, let element = tuple.elements.first, element.label == nil else { return [] }
            return literals(in: element.expression)
        }
        if let cast = expression.as(AsExprSyntax.self) { return literals(in: cast.expression) }
        // Calls include localization entry points and helpers with technical arguments.
        // Nested presentation calls (such as a TextField's Text prompt) have their own visitor.
        return []
    }
}
