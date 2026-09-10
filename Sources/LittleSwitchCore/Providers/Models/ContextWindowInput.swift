import Foundation

public enum ContextWindowInput {
    public enum Error: Swift.Error, Equatable {
        case invalid
    }

    public static func parse(_ input: String) throws -> Int? {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return nil
        }

        let multiplier: Int
        let digits: String
        if normalized.hasSuffix("k") {
            multiplier = 1_000
            digits = String(normalized.dropLast())
        } else if normalized.hasSuffix("m") {
            multiplier = 1_000_000
            digits = String(normalized.dropLast())
        } else {
            multiplier = 1
            digits = normalized
        }

        guard let value = Int(digits), value > 0 else {
            throw Error.invalid
        }
        let result = value.multipliedReportingOverflow(by: multiplier)
        guard !result.overflow, result.partialValue > 0 else {
            throw Error.invalid
        }
        return result.partialValue
    }
}
