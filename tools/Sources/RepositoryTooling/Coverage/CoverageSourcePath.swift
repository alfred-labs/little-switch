import Foundation

enum CoverageSourcePath {
    static func validate(_ path: String, location: String) throws {
        try validateRelative(path, location: location)
        guard path.utf8.starts(with: "Sources/".utf8) else {
            throw CoverageValidationError(
                "\(location): exclusion path must be package-relative under Sources/: \(path)")
        }
        guard path.hasSuffix(".swift") else {
            throw CoverageValidationError("\(location): exclusion path must name a .swift source: \(path)")
        }
    }

    static func validateRelative(_ path: String, location: String) throws {
        guard !path.isEmpty else {
            throw CoverageValidationError("\(location): path is missing")
        }
        guard !containsControl(path) else {
            throw CoverageValidationError("\(location): path contains a control character: \(String(reflecting: path))")
        }
        guard !path.contains("\\") else {
            throw CoverageValidationError("\(location): paths must use forward slashes: \(path)")
        }
        guard !path.utf8.starts(with: "/".utf8), path.firstMatch(of: /^[A-Za-z]:\//) == nil else {
            throw CoverageValidationError("\(location): path must not be absolute: \(path)")
        }
        guard path.rangeOfCharacter(from: CharacterSet(charactersIn: "*?[]{}")) == nil else {
            throw CoverageValidationError("\(location): wildcard paths are not allowed: \(path)")
        }
        let components = path.components(separatedBy: "/")
        guard !components.contains("..") else {
            throw CoverageValidationError("\(location): path traversal is not allowed: \(path)")
        }
        guard !components.contains(where: { $0.isEmpty || $0 == "." }) else {
            throw CoverageValidationError("\(location): path must be normalized: \(path)")
        }
    }

    static func containsControl(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }
}
