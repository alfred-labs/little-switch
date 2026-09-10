enum DiagnosticJSONNumber {
    static func floating(_ number: Double) -> String {
        if number.isInfinite { return number.sign == .minus ? "-Infinity" : "Infinity" }
        let description = number.description
        // Python keeps this exponent in fixed notation. Move the decimal point
        // in Swift's shortest representation without introducing another rounding.
        guard description.hasSuffix("e+15") else { return description }
        let sign = description.hasPrefix("-") ? "-" : ""
        let digits = description.dropLast(4).filter { $0 != "." && $0 != "-" }
        let point = digits.index(digits.startIndex, offsetBy: min(16, digits.count))
        let whole = digits[..<point] + String(repeating: "0", count: max(0, 16 - digits.count))
        let fraction = digits[point...]
        return sign + whole + "." + (fraction.isEmpty ? "0" : String(fraction))
    }
}
