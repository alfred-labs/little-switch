import Foundation

struct RepositoryTextRule: Sendable {
    let path: String
    let required: [String]
    let forbidden: [String]

    init(_ path: String, required: [String] = [], forbidden: [String] = []) {
        self.path = path
        self.required = required
        self.forbidden = forbidden
    }

    func violations(in files: [String: String]) -> [String] {
        guard let contents = files[path] else { return ["Missing policy file: \(path)"] }
        var issues = required.filter { contents.range(of: $0, options: .regularExpression) == nil }
            .map { "\(path): required contract is missing: \($0)" }
        issues += forbidden.filter { contents.range(of: $0, options: .regularExpression) != nil }
            .map { "\(path): forbidden contract is present: \($0)" }
        return issues
    }
}
