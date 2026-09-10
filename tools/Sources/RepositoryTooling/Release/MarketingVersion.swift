import Foundation

struct MarketingVersion: Comparable, Sendable {
    private let components: [String]

    init(_ value: String) throws {
        let parts = value.components(separatedBy: ".")
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } })
        else {
            throw ReleaseValidationError("Marketing version must contain three numeric components on one line")
        }
        components = parts.map { String($0.drop { $0 == "0" }) }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        for (left, right) in zip(lhs.components, rhs.components) where left != right {
            return left.count == right.count ? left < right : left.count < right.count
        }
        return false
    }
}
